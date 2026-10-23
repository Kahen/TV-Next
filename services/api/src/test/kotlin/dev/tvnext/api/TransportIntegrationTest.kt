package dev.tvnext.api
import java.net.InetAddress
import java.net.ServerSocket
import java.net.URI
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import kotlin.test.*
import org.springframework.mock.web.MockHttpServletRequest
import org.springframework.mock.web.MockHttpServletResponse
import jakarta.servlet.FilterChain

class TransportIntegrationTest {
    @Test fun pinnedSocketSendsOriginalHostAndJsonPostAndReadsBoundedGzip() {
        ServerSocket(0,1,InetAddress.getLoopbackAddress()).use { server ->
            val request = CompletableFuture<String>()
            val worker = Thread.ofVirtual().start {
                server.accept().use { socket ->
                    socket.soTimeout = 3000
                    val reader = socket.getInputStream().bufferedReader(Charsets.ISO_8859_1)
                    val headers = mutableListOf<String>(); var length = 0
                    while (true) {
                        val line = reader.readLine() ?: error("Missing request")
                        if (line.isEmpty()) break
                        headers += line
                        if (line.startsWith("Content-Length:")) length = line.substringAfter(':').trim().toInt()
                    }
                    val body = CharArray(length)
                    var offset = 0
                    while (offset < length) { val count = reader.read(body,offset,length-offset); check(count>0);offset+=count }
                    request.complete(headers.joinToString("\n")+"\n"+String(body))
                    val compressed = java.io.ByteArrayOutputStream().also { out -> java.util.zip.GZIPOutputStream(out).use { it.write("{\"ok\":true}".toByteArray()) } }.toByteArray()
                    socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: ${compressed.size}\r\n\r\n".toByteArray())
                    socket.getOutputStream().write(compressed)
                }
            }
            val result = ProviderTransport().exchange(URI("http://provider.invalid:${server.localPort}/api"),InetAddress.getLoopbackAddress(),mapOf("Authorization" to "own-token"),"{\"path\":\"/\"}","application/json")
            assertEquals("{\"ok\":true}",result)
            val raw = request.get(3,TimeUnit.SECONDS)
            assertTrue(raw.startsWith("POST /api HTTP/1.1"));assertTrue(raw.contains("Host: provider.invalid:${server.localPort}"))
            assertTrue(raw.contains("Content-Type: application/json"));assertTrue(raw.endsWith("{\"path\":\"/\"}"))
            worker.join(3000)
        }
    }
    @Test fun envelopeLimitAlsoAppliesWhenLengthIsUnknownAndRateIsPerActualPeer() {
        val filter = ApiRequestLimits()
        val request = MockHttpServletRequest("POST","/api/v1/resources/text").apply { setContent(ByteArray(3_145_729));remoteAddr="127.0.0.1" }
        val response = MockHttpServletResponse()
        var reached = false
        filter.doFilter(request,response,FilterChain { _,_ -> reached=true })
        assertEquals(413,response.status);assertFalse(reached)
        val rateFilter = ApiRequestLimits()
        repeat(301) { index ->
            val r = MockHttpServletRequest("POST","/api/v1/resources/text").apply { setContent("{}".toByteArray());remoteAddr="127.0.0.2";addHeader("X-Forwarded-For","1.2.3.$index") }
            val out = MockHttpServletResponse()
            rateFilter.doFilter(r,out,FilterChain { _,_ -> })
            assertEquals(if(index<300)200 else 429,out.status)
        }
    }
}
