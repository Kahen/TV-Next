package dev.tvnext.api

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.*
import java.nio.charset.StandardCharsets
import java.util.concurrent.Semaphore
import javax.net.ssl.*
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.web.server.ResponseStatusException

/** GET only, pinned IP, verified TLS hostname; no redirects, inherited proxy, cookies or caller headers. */
@Component
open class ProviderTransport(@Value("\${TV_NEXT_LAN_ORIGINS:}") allowedPrivate: String = "") {
    private val lanOrigins = allowedPrivate.split(',').map { it.trim() }.filter { it.isNotEmpty() }.map { origin(Subscriptions.httpUri(it)) }.toSet()
    private fun origin(uri: URI) = "${uri.scheme.lowercase()}://${uri.host.lowercase()}:${if (uri.port != -1) uri.port else if (uri.scheme == "https") 443 else 80}"
    private fun allowed(uri: URI, address: InetAddress) = publicAddress(address) ||
        origin(uri) in lanOrigins && address.isSiteLocalAddress && !address.isLoopbackAddress && !address.isLinkLocalAddress

    private val permits = Semaphore(8)
    open fun get(uri: URI, headers: Map<String, String> = emptyMap(), form: String? = null): String = perform(uri, headers, form, "application/x-www-form-urlencoded")
    open fun postJson(uri: URI, headers: Map<String,String>, json: String): String = perform(uri, headers, json, "application/json")
    private fun perform(uri: URI, headers: Map<String,String>, form: String?, contentType: String): String {
        Subscriptions.httpUri(uri.toString())
        validateHeaders(headers)
        if (!permits.tryAcquire()) throw ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "Provider concurrency limit")
        try {
            val addresses = InetAddress.getAllByName(uri.host)
            if (addresses.isEmpty() || addresses.any { !allowed(uri,it) })
                throw ResponseStatusException(HttpStatus.BAD_GATEWAY, "Forbidden provider address")
            return exchange(uri, addresses.first(), headers, form, contentType)
        } catch (e: ResponseStatusException) { throw e }
        catch (_: Exception) { throw ResponseStatusException(HttpStatus.BAD_GATEWAY, "Provider transport failed") }
        finally { permits.release() }
    }
    internal fun exchange(uri: URI, address: InetAddress, headers: Map<String, String> = emptyMap(), form: String? = null, contentType: String = "application/x-www-form-urlencoded"): String {
        val deadline = System.nanoTime() + 8_000_000_000L
        val port = if (uri.port != -1) uri.port else if (uri.scheme == "https") 443 else 80
        val plain = Socket()
        try {
            plain.connect(InetSocketAddress(address, port), 3000)
            plain.soTimeout = 3000
            val socket = if (uri.scheme == "https") {
                val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(plain, uri.host, port, true) as SSLSocket
                ssl.sslParameters = SSLParameters().apply {
                    endpointIdentificationAlgorithm = "HTTPS"
                    if (!uri.host.contains(':') && !uri.host.matches(Regex("[0-9.]+"))) serverNames = listOf(SNIHostName(uri.host))
                }
                ssl.startHandshake()
                ssl
            } else plain
            socket.use {
                val wire = URI(uri.toASCIIString())
                val path = (wire.rawPath.takeIf { p -> !p.isNullOrEmpty() } ?: "/") + (wire.rawQuery?.let { q -> "?$q" } ?: "")
                val host = if (uri.host.contains(':')) "[${uri.host}]" else uri.host
                val authority = host + if (uri.port == -1) "" else ":${uri.port}"
                val body = form?.toByteArray(StandardCharsets.UTF_8)
                if ((body?.size ?: 0) > MAX_BYTES) throw java.io.IOException("Request body limit")
                val extra = headers.entries.joinToString("") { h -> "${h.key}: ${h.value}\r\n" }
                val request = "${if (body == null) "GET" else "POST"} $path HTTP/1.1\r\nHost: $authority\r\n" +
                    "Accept: application/json, application/xml, text/plain\r\nAccept-Encoding: gzip\r\nConnection: close\r\n" +
                    extra + (if (body == null) "" else "Content-Type: $contentType\r\nContent-Length: ${body.size}\r\n") + "\r\n"
                it.getOutputStream().write(request.toByteArray(StandardCharsets.ISO_8859_1))
                if (body != null) it.getOutputStream().write(body)
                val input = it.getInputStream().buffered()
                fun readByte(): Int {
                    if (Thread.currentThread().isInterrupted) throw java.io.InterruptedIOException()
                    val remaining = (deadline - System.nanoTime()) / 1_000_000
                    if (remaining <= 0) throw SocketTimeoutException()
                    socket.soTimeout = minOf(remaining, 3000).toInt().coerceAtLeast(1)
                    return input.read()
                }
                return parseResponse(object : InputStream() { override fun read() = readByte() })
            }
        } finally { plain.close() }
    }
    companion object {
        internal fun validateHeaders(headers: Map<String, String>) {
            val forbidden = setOf("host", "connection", "content-length", "transfer-encoding", "accept-encoding", "content-type", "upgrade", "proxy-authorization", "proxy-connection", "te", "trailer")
            if (headers.size > 32 || headers.entries.sumOf { it.key.length + it.value.length } > 16384 ||
                headers.keys.map { it.lowercase() }.distinct().size != headers.size || headers.any { (key, value) ->
                    !key.matches(Regex("[a-zA-Z0-9_-]{1,64}")) || key.lowercase() in forbidden ||
                    value.any { it.code < 32 || it.code >= 127 }
                }) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid provider headers")
        }
        const val MAX_BYTES = 1_048_576
        internal fun publicAddress(address: InetAddress): Boolean {
            val b = address.address.map { it.toInt() and 255 }
            if (address.isAnyLocalAddress || address.isLoopbackAddress || address.isLinkLocalAddress || address.isSiteLocalAddress || address.isMulticastAddress) return false
            if (b.size == 4) return !(b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
                b[0] == 169 && b[1] == 254 || b[0] == 172 && b[1] in 16..31 ||
                b[0] == 192 && (b[1] == 168 || b[1] == 0 || b[1] == 2) ||
                b[0] == 100 && b[1] in 64..127 || b[0] == 198 && b[1] in listOf(18, 19, 51) ||
                b[0] == 203 && b[1] == 0 && b[2] == 113)
            return b.size == 16 && b[0] in 0x20..0x3f &&
                !(b[0] == 0x20 && b[1] == 0x01 && (b[2] < 2 || b[2] == 0x0d && b[3] == 0xb8)) && !(b[0] == 0x20 && b[1] == 0x02)
        }
        internal fun parseResponse(input: InputStream): String {
            var headerBytes = 0
            fun line(limit: Int = 8192): String {
                val out = ByteArrayOutputStream()
                while (true) {
                    val c = input.read()
                    if (c == -1) throw java.io.IOException("Truncated HTTP response")
                    headerBytes++
                    if (headerBytes > 32768 || out.size() > limit) throw java.io.IOException("Header limit")
                    if (c == 10) {
                        val bytes = out.toByteArray()
                        if (bytes.isEmpty() || bytes.last() != 13.toByte()) throw java.io.IOException("Expected CRLF")
                        return String(bytes, 0, bytes.size - 1, StandardCharsets.ISO_8859_1)
                    }
                    out.write(c)
                }
            }
            if (!line().matches(Regex("HTTP/1\\.[01] 200(?: .*)?"))) throw java.io.IOException("Only HTTP 200 accepted")
            val headers = mutableMapOf<String, String>()
            while (true) {
                val value = line()
                if (value.isEmpty()) break
                val split = value.indexOf(':')
                if (split < 1 || value[0].isWhitespace()) throw java.io.IOException("Malformed header")
                if (headers.put(value.substring(0, split).lowercase(), value.substring(split + 1).trim()) != null) throw java.io.IOException("Duplicate header")
            }
            if (headers["content-encoding"]?.lowercase() !in listOf(null, "identity", "gzip")) throw java.io.IOException("Compressed response rejected")
            val transfer = headers["transfer-encoding"]?.lowercase()
            if (transfer != null && transfer != "chunked" || transfer != null && headers.containsKey("content-length")) throw java.io.IOException("Ambiguous body")
            val body = ByteArrayOutputStream()
            fun copy(count: Long) {
                if (count < 0 || count > MAX_BYTES - body.size()) throw java.io.IOException("Provider body limit")
                repeat(count.toInt()) { val c = input.read(); if (c == -1) throw java.io.IOException("Truncated body"); body.write(c) }
            }
            when {
                transfer == "chunked" -> while (true) {
                    val length = line(100).substringBefore(';').trim().toLongOrNull(16) ?: throw java.io.IOException("Invalid chunk")
                    if (length == 0L) { while (line().isNotEmpty()) {}; break }
                    copy(length)
                    if (input.read() != 13 || input.read() != 10) throw java.io.IOException("Chunk delimiter")
                }
                headers.containsKey("content-length") -> copy(headers.getValue("content-length").toLongOrNull() ?: throw java.io.IOException("Invalid length"))
                else -> while (true) {
                    val c = input.read(); if (c == -1) break
                    if (body.size() >= MAX_BYTES) throw java.io.IOException("Provider body limit")
                    body.write(c)
                }
            }
            val bytes = if (headers["content-encoding"]?.lowercase() == "gzip") {
                java.util.zip.GZIPInputStream(body.toByteArray().inputStream()).use {
                    val decoded = it.readNBytes(MAX_BYTES + 1)
                    if (decoded.size > MAX_BYTES) throw java.io.IOException("Decompressed body limit")
                    decoded
                }
            } else body.toByteArray()
            return StandardCharsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
        }
    }
}
