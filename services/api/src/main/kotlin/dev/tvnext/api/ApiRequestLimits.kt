package dev.tvnext.api

import jakarta.servlet.FilterChain
import jakarta.servlet.ReadListener
import jakarta.servlet.ServletInputStream
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletRequestWrapper
import jakarta.servlet.http.HttpServletResponse
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import org.springframework.core.annotation.Order
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter

/** Bounded JSON envelope and per-peer request rate. Forwarded headers never define the peer. */
@Component
@Order(1)
class ApiRequestLimits : OncePerRequestFilter() {
    private data class Window(val minute: Long, var count: Int)
    private val windows = ConcurrentHashMap<String,Window>()
    override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
        if (!request.requestURI.startsWith("/api/v1/") || request.method !in setOf("POST","GET")) { chain.doFilter(request,response); return }
        val now = System.currentTimeMillis() / 60_000
        val accepted = synchronized(windows) {
            if (windows.size >= 4096) windows.entries.removeIf { it.value.minute != now }
            val auth = request.requestURI.startsWith("/api/v1/home/auth/") || request.requestURI == "/api/v1/home/pairings/claim"
            val peer = request.remoteAddr + if (auth) ":auth" else ":api"
            if (!windows.containsKey(peer) && windows.size >= 4096) false else {
                val window = windows[peer]?.takeIf { it.minute == now } ?: Window(now,0).also { windows[peer] = it }
                window.count++; window.count <= if (auth) 10 else 300
            }
        }
        fun reject(code: Int, message: String) {
            response.status = code; response.contentType = "application/json"; response.characterEncoding = "UTF-8"
            if (code == 429) response.setHeader("Retry-After","60")
            response.writer.write("{\"error\":\"$message\"}")
        }
        if (!accepted) { reject(429,"API request rate limit"); return }
        if (request.method=="GET") { chain.doFilter(request,response);return }
        val max = 3_145_728
        if (request.contentLengthLong > max) { reject(413,"Request envelope exceeds 3 MiB"); return }
        val bytes = request.inputStream.readNBytes(max + 1)
        if (bytes.size > max) { reject(413,"Request envelope exceeds 3 MiB"); return }
        val wrapped = object : HttpServletRequestWrapper(request) {
            override fun getInputStream(): ServletInputStream {
                val input = bytes.inputStream()
                return object : ServletInputStream() {
                    override fun read() = input.read()
                    override fun read(b: ByteArray, off: Int, len: Int) = input.read(b,off,len)
                    override fun isFinished() = input.available() == 0
                    override fun isReady() = true
                    override fun setReadListener(listener: ReadListener?) { throw UnsupportedOperationException("Synchronous JSON API") }
                }
            }
            override fun getReader() = BufferedReader(InputStreamReader(inputStream,Charsets.UTF_8))
        }
        chain.doFilter(wrapped,response)
    }
}
