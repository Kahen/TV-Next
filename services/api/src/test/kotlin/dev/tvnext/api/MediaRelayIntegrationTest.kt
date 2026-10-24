package dev.tvnext.api

import com.fasterxml.jackson.databind.ObjectMapper
import java.io.Closeable
import java.net.URI
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.*
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.context.TestConfiguration
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Primary
import org.springframework.http.MediaType
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

@SpringBootTest(properties=["TV_NEXT_REGISTRATION_OPEN=true"])
@AutoConfigureMockMvc
class MediaRelayIntegrationTest @Autowired constructor(private val accounts: HomeAccounts,private val mvc: MockMvc,
    private val mapper: ObjectMapper,private val upstream: FixtureMediaTransport) {
    class FixtureMediaTransport: MediaTransport(ProviderTransport()) {
        data class Request(val uri: URI,val headers: Map<String,String>,val range: String?)
        val requests=CopyOnWriteArrayList<Request>()
        val entered=CountDownLatch(1)
        val disconnected=CountDownLatch(1)
        override fun fetch(initial: URI,initialHeaders: Map<String,String>,range: String?,head: Boolean): MediaResponse {
            requests+=Request(initial,initialHeaders,range)
            if(initial.path=="/blocked.mp4")return MediaResponse(initial,200,mapOf("content-type" to "video/mp4"),object: java.io.InputStream() {
                override fun read(): Int { entered.countDown();check(disconnected.await(5,TimeUnit.SECONDS));throw java.io.IOException("Fixture connection closed") }
            },Closeable { disconnected.countDown() })
            val manifest=initial.path.endsWith("m3u8")
            val body=if(initial.path.endsWith("subtitles.m3u8"))"#EXTM3U\n#EXTINF:6,\ncaptions.vtt\n".toByteArray()
                else if(initial.path.endsWith(".vtt"))"WEBVTT\n\n00:00.000 --> 00:06.000\nSubtitle fixture\n".toByteArray()
                else if(manifest)"#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",URI=\"subtitles.m3u8\"\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXTINF:6,\npiece.ts\nhttps://cdn.example.org/other.ts\n".toByteArray() else byteArrayOf(0,1,2,3)
            return MediaResponse(initial,if(range!=null)206 else 200,mapOf("content-type" to if(manifest)"application/vnd.apple.mpegurl" else if(initial.path.endsWith(".vtt"))"text/vtt; charset=utf-8" else "video/mp4","content-length" to body.size.toString())+
                if(range!=null)mapOf("content-range" to "bytes 0-3/10") else emptyMap(),if(head)byteArrayOf().inputStream() else body.inputStream(),Closeable { })
        }
    }
    @TestConfiguration class Config { @Bean @Primary fun mediaFixture()=FixtureMediaTransport() }
    private fun user()=accounts.register(Credentials("relay-"+UUID.randomUUID(),"long-test-password","Player"))
    private fun create(s: HomeSession,url: String="https://example.org/media/master.m3u8"): String {
        val content=mapper.writeValueAsString(MediaRelayRequest(url,mapOf("Cookie" to "only-upstream","Referer" to "https://example.org/")))
        val response=mvc.perform(post("/api/v1/home/media/sessions").header("Authorization","Bearer "+s.token).contentType(MediaType.APPLICATION_JSON).content(content)).andExpect(status().isOk).andReturn().response.contentAsString
        assertFalse(response.contains(s.token));assertFalse(response.contains("only-upstream"));assertFalse(response.contains("example.org"))
        return mapper.readTree(response).path("path").asText()
    }
    @Test fun sessionRequiresLoginAndRewritesNestedResourcesWithoutLeakingCredentials() {
        mvc.perform(post("/api/v1/home/media/sessions").contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isUnauthorized)
        val owner=user();val path=create(owner)
        val result=mvc.perform(get(path)).andExpect(status().isOk).andReturn().response
        assertEquals("no-store, private",result.getHeader("Cache-Control"));assertEquals("nosniff",result.getHeader("X-Content-Type-Options"))
        assertFalse(result.contentAsString.contains("example.org"));assertTrue(result.contentAsString.contains("#EXT-X-KEY"))
        val lines=result.contentAsString.lines().filter { it.startsWith("/api/") }
        mvc.perform(get(lines[0])).andExpect(status().isOk)
        assertEquals("only-upstream",upstream.requests.last().headers["Cookie"])
        mvc.perform(get(lines[1])).andExpect(status().isOk)
        assertTrue(upstream.requests.last().headers.isEmpty())
        val stranger=user();val close=path.substringBeforeLast('/')+"/close"
        mvc.perform(post(close).header("Authorization","Bearer "+stranger.token)).andExpect(status().isNotFound)
        mvc.perform(post(close).header("Authorization","Bearer "+owner.token)).andExpect(status().isOk)
        mvc.perform(get(path)).andExpect(status().isUnauthorized)
    }
    @Test fun nestedHlsSubtitleRenditionsAllowWebVttWithoutAcceptingAnArbitraryRootTextFile() {
        val owner=user();val path=create(owner)
        val master=mvc.perform(get(path)).andExpect(status().isOk).andReturn().response.contentAsString
        val subtitle=Regex("#EXT-X-MEDIA:[^\n]*URI=\"([^\"]+)\"").find(master)!!.groupValues[1]
        val playlist=mvc.perform(get(subtitle)).andExpect(status().isOk).andReturn().response.contentAsString
        val segment=playlist.lines().first { it.startsWith("/api/") }
        val response=mvc.perform(get(segment)).andExpect(status().isOk).andReturn().response
        assertEquals("text/vtt",response.contentType);assertTrue(response.contentAsString.contains("Subtitle fixture"))
        assertEquals("only-upstream",upstream.requests.last().headers["Cookie"])
        mvc.perform(get(create(owner,"https://example.org/captions.vtt"))).andExpect(status().isBadGateway)
    }
    @Test fun supportsHeadAndRangeAndDeviceRevocationInvalidatesPreviouslyIssuedUrls() {
        val owner=user();val path=create(owner,"https://example.org/movie.mp4")
        mvc.perform(head(path)).andExpect(status().isOk).andReturn().response.let { assertEquals(0,it.contentAsByteArray.size);assertEquals("video/mp4",it.contentType) }
        val result=mvc.perform(get(path).header("Range","bytes=0-")).andExpect(status().isPartialContent).andReturn().response
        assertContentEquals(byteArrayOf(0,1,2,3),result.contentAsByteArray)
        assertEquals("bytes=0-8388607",upstream.requests.last().range)
        mvc.perform(get(path).header("Range","bytes=0-1,4-5")).andExpect(status().isRequestedRangeNotSatisfiable)
        accounts.revoke(accounts.principal("Bearer "+owner.token),owner.device.id)
        mvc.perform(get(path)).andExpect(status().isUnauthorized)
    }
    @Test fun revocationClosesAnInflightSocketRatherThanWaitingForTheNextRequest() {
        val owner=user();val path=create(owner,"https://example.org/blocked.mp4")
        java.util.concurrent.Executors.newSingleThreadExecutor().use { pool ->
            val transfer=pool.submit { mvc.perform(get(path)).andExpect(status().isBadGateway) }
            assertTrue(upstream.entered.await(5,TimeUnit.SECONDS))
            accounts.revoke(accounts.principal("Bearer "+owner.token),owner.device.id)
            assertTrue(upstream.disconnected.await(1,TimeUnit.SECONDS))
            transfer.get(5,TimeUnit.SECONDS)
        }
        mvc.perform(get(path)).andExpect(status().isUnauthorized)
    }
}
