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
    @Test fun redirectsRevalidateDestinationStripCredentialsAndRetainFinalBaseUri() {
        val address=java.net.NetworkInterface.getNetworkInterfaces().toList().flatMap { it.inetAddresses.toList() }
            .firstOrNull { it is java.net.Inet4Address && it.isSiteLocalAddress && !it.isLoopbackAddress }
        org.junit.jupiter.api.Assumptions.assumeTrue(address!=null,"LAN interface required for explicit-origin loopback-free test")
        address!!
        ServerSocket(0,1,address).use { first -> ServerSocket(0,1,address).use { second ->
            first.soTimeout=3000;second.soTimeout=3000
            val a="http://${address.hostAddress}:${first.localPort}"
            val b="http://${address.hostAddress}:${second.localPort}"
            val received=CompletableFuture<String>()
            val one=Thread.ofVirtual().start {
                first.accept().use { socket ->
                    val reader=socket.getInputStream().bufferedReader()
                    while(!reader.readLine().isNullOrEmpty()) {}
                    socket.getOutputStream().write("HTTP/1.1 302 Found\r\nLocation: $b/path/config.json\r\nContent-Length: 0\r\n\r\n".toByteArray())
                }
            }
            val two=Thread.ofVirtual().start {
                second.accept().use { socket ->
                    val reader=socket.getInputStream().bufferedReader();val lines=mutableListOf<String>()
                    while(true){ val line=reader.readLine() ?: break;if(line.isEmpty())break;lines+=line }
                    received.complete(lines.joinToString("\n"))
                    socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".toByteArray())
                }
            }
            val fetched=ProviderTransport("$a,$b").getDocument(URI("$a/start"),mapOf("Authorization" to "own-secret"))
            assertEquals("{}",fetched.content);assertEquals("$b/path/config.json",fetched.uri.toString())
            assertFalse(received.get(3,TimeUnit.SECONDS).contains("own-secret"))
            one.join(3000);two.join(3000)
        } }
    }
    @Test fun globalAdmissionBoundsConcurrentRequestsAndReleasesSlots() {
        val filter=ApiRequestLimits()
        val entered=java.util.concurrent.CountDownLatch(8)
        val release=java.util.concurrent.CountDownLatch(1)
        val pool=java.util.concurrent.Executors.newFixedThreadPool(8)
        try {
            val work=(0 until 8).map { index -> pool.submit {
                val request=MockHttpServletRequest("GET","/api/v1/home/library").apply { remoteAddr="192.0.2."+index }
                filter.doFilter(request,MockHttpServletResponse(),FilterChain { _,_ -> entered.countDown();assertTrue(release.await(5,TimeUnit.SECONDS)) })
            } }
            assertTrue(entered.await(5,TimeUnit.SECONDS))
            val rejected=MockHttpServletResponse()
            filter.doFilter(MockHttpServletRequest("GET","/api/v1/home/library"),rejected,FilterChain { _,_ -> fail("Ninth request must wait for capacity") })
            assertEquals(429,rejected.status)
            release.countDown();work.forEach { it.get(5,TimeUnit.SECONDS) }
            var reached=false
            filter.doFilter(MockHttpServletRequest("GET","/api/v1/home/library"),MockHttpServletResponse(),FilterChain { _,_ -> reached=true })
            assertTrue(reached)
        } finally { release.countDown();pool.shutdownNow() }
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
