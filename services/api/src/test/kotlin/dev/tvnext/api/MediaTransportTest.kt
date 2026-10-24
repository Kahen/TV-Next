package dev.tvnext.api

import java.io.*
import java.net.*
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import kotlin.test.*

class MediaTransportTest {
    private fun response(raw: String,head: Boolean=false)=MediaTransport.readResponse(URI("https://example.org/media"),raw.toByteArray(Charsets.ISO_8859_1).inputStream(),Closeable { },head)
    @Test fun clampsSingleRangesAndRejectsAmbiguousOrInvertedRanges() {
        assertEquals("bytes=10-8388617",MediaTransport.boundedRange("bytes=10-"))
        assertEquals("bytes=-8388608",MediaTransport.boundedRange("bytes=-99999999"))
        assertEquals("bytes=0-1",MediaTransport.boundedRange("bytes=0-1"))
        listOf("bytes=9-1","bytes=-0","bytes=-","bytes=0-1,4-5","bytes=0-1\r\nX: y").forEach { assertFails { MediaTransport.boundedRange(it) } }
    }
    @Test fun validatesBinaryFramingRangesChunkingAndHeadWithoutDecodingMedia() {
        response("HTTP/1.1 206 Partial Content\r\nContent-Length: 4\r\nContent-Range: bytes 2-5/10\r\nContent-Type: video/mp4\r\n\r\n\u0000\u00ffAB").use {
            assertEquals(206,it.status);assertContentEquals(byteArrayOf(0,-1,65,66),it.body.readAllBytes())
        }
        response("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nAB\r\n2\r\nCD\r\n0\r\nX-Trailer: ignored\r\n\r\n").use { assertEquals("ABCD",it.body.readAllBytes().toString(Charsets.UTF_8)) }
        response("HTTP/1.1 200 OK\r\nContent-Length: 999999999\r\n\r\n",true).use { assertEquals(-1,it.body.read()) }
        listOf(
            "Content-Length: 2\r\nContent-Length: 2",
            "Content-Length: 2\r\nTransfer-Encoding: chunked",
            "Content-Encoding: gzip",
            "Content-Length: 999999999"
        ).forEach { h -> assertFails { response("HTTP/1.1 200 OK\r\n$h\r\n\r\nAB").body.readAllBytes() } }
        assertFails { response("HTTP/1.1 206 OK\r\nContent-Length: 3\r\nContent-Range: bytes 0-1/10\r\n\r\nABC") }
        assertFails { response("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nAB").body.readAllBytes() }
        assertFails { response("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2000001\r\n").body.readAllBytes() }
    }
    @Test fun pinsSocketAndStripsCredentialsWhenFollowingCrossOriginRedirects() {
        val policy=object: ProviderTransport() { override fun resolveAddress(uri: URI)=InetAddress.getLoopbackAddress() }
        val transport=MediaTransport(policy)
        ServerSocket(0,1,InetAddress.getLoopbackAddress()).use { first -> ServerSocket(0,1,InetAddress.getLoopbackAddress()).use { second ->
            first.soTimeout=3000;second.soTimeout=3000
            val request=CompletableFuture<String>()
            val one=Thread.ofVirtual().start { first.accept().use { s ->
                s.soTimeout=3000;val reader=s.getInputStream().bufferedReader();while(!reader.readLine().isNullOrEmpty()){}
                s.getOutputStream().write("HTTP/1.1 302 Found\r\nLocation: http://cdn.invalid:${second.localPort}/part\r\nContent-Length: 0\r\n\r\n".toByteArray())
            } }
            val two=Thread.ofVirtual().start { second.accept().use { s ->
                s.soTimeout=3000;val reader=s.getInputStream().bufferedReader();val lines=mutableListOf<String>()
                while(true){val line=reader.readLine() ?: break;if(line.isEmpty())break;lines+=line};request.complete(lines.joinToString("\n"))
                s.getOutputStream().write("HTTP/1.1 206 OK\r\nContent-Length: 2\r\nContent-Range: bytes 0-1/4\r\n\r\nAB".toByteArray())
            } }
            transport.fetch(URI("http://source.invalid:${first.localPort}/movie"),mapOf("Cookie" to "private-cookie","Authorization" to "secret"),"bytes=0-1").use { assertEquals("AB",it.body.readAllBytes().toString(Charsets.UTF_8)) }
            val wire=request.get(3,TimeUnit.SECONDS)
            assertTrue(wire.contains("Host: cdn.invalid:${second.localPort}"));assertTrue(wire.contains("Range: bytes=0-1"))
            assertFalse(wire.contains("private-cookie"));assertFalse(wire.contains("secret"))
            one.join(3000);two.join(3000)
        } }
        assertFails { MediaTransport(ProviderTransport()).fetch(URI("http://127.0.0.1/secret"),emptyMap(),null) }
    }
    @Test fun rewritesEveryHlsResourceAgainstTheFinalDocumentAndRejectsUnsupportedSchemes() {
        val urls=mutableListOf<String>()
        val text="""#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,URI="audio.m3u8"
#EXT-X-KEY:METHOD=AES-128,URI="../key?auth=1"
#EXT-X-MAP:URI="init.mp4"
#EXT-X-PART:DURATION=1,URI="part.m4s"
#EXT-X-PRELOAD-HINT:TYPE=PART,URI="next.m4s"
#EXT-X-STREAM-INF:BANDWIDTH=100
video/main.m3u8
https://cdn.example.org/seg.ts
"""
        val rewritten=MediaRelay.rewrite(text,URI("https://example.org/final/index.m3u8")) { urls+=it.toString();"/local/${urls.size}" }
        assertEquals(7,urls.size);assertEquals("https://example.org/key?auth=1",urls[1]);assertTrue(rewritten.contains("URI=\"/local/3\""));assertFalse(rewritten.contains("auth=1"))
        listOf("skd://key","file:///secret","javascript:alert(1)","{\$variable}/seg.ts").forEach { raw -> assertFails { MediaRelay.rewrite("#EXTM3U\n$raw",URI("https://example.org/")) { "/x" } } }
        assertFails { MediaRelay.rewrite("#EXTM3U\n#EXT-X-KEY:URI=unquoted",URI("https://example.org/")) { "/x" } }
    }
}
