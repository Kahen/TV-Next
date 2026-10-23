package dev.tvnext.api

import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URI
import java.util.UUID
import kotlin.test.*
import org.junit.jupiter.api.AfterEach
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.*
import org.springframework.web.server.ResponseStatusException

@SpringBootTest(properties=["TV_NEXT_REGISTRATION_OPEN=true","TV_NEXT_EPG_INITIAL_DELAY_MS=3600000"])
@AutoConfigureMockMvc
class EpgFeedIntegrationTest @Autowired constructor(private val db: JdbcTemplate,private val accounts: HomeAccounts,
    private val feeds: EpgFeeds,private val mvc: MockMvc,private val mapper: ObjectMapper) {
    private fun user()=accounts.register(Credentials("epg-"+UUID.randomUUID(),"long-test-password","EPG test"))
    private val xml="""<tv><channel id="news"><display-name>News</display-name></channel><programme channel="news" start="20261023120000 +0800" stop="20261023130000 +0800"><title>今日新闻</title></programme></tv>"""
    private fun guideRequest()=EpgFeedGuideRequest(listOf(EpgChannelRequest("news","News")),"2026-10-23T04:30:00Z",12)
    @AfterEach fun cleanup() { db.update("DELETE FROM epg_feeds") }

    @Test fun persistentFeedsAreUserScopedAndHttpRequiresAuthentication() {
        val one=user();val two=user()
        mvc.perform(get("/api/v1/home/epg/feeds")).andExpect(status().isUnauthorized)
        val saved=feeds.create(one.user.id,EpgFeedWrite("News","https://example.org/guide.xml.gz"))
        assertFalse(saved.available);assertEquals(1,feeds.list(one.user.id).size)
        assertTrue(feeds.list(two.user.id).isEmpty())
        val fresh=EpgFeeds(db,ProviderTransport(),XmltvGuideService())
        assertEquals(saved,fresh.list(one.user.id).single())
        mvc.perform(post("/api/v1/home/epg/feeds/${saved.id}/remove").header("Authorization","Bearer "+two.token)).andExpect(status().isNotFound)
        mvc.perform(post("/api/v1/home/epg/feeds/${saved.id}/guide").header("Authorization","Bearer "+two.token).contentType(MediaType.APPLICATION_JSON).content(mapper.writeValueAsBytes(guideRequest()))).andExpect(status().isNotFound)
        accounts.revoke(accounts.principal("Bearer "+one.token),one.device.id)
        mvc.perform(get("/api/v1/home/epg/feeds").header("Authorization","Bearer "+one.token)).andExpect(status().isUnauthorized)
    }
    @Test fun refreshPersistsValidatedXmlAndFailureRetainsLastGoodCache() {
        val session=user();val saved=feeds.create(session.user.id,EpgFeedWrite("News","https://example.org/guide.xml.gz"))
        var response=xml
        val transport=object:ProviderTransport() { override fun get(uri: URI,headers: Map<String,String>,form: String?)=response }
        val service=EpgFeeds(db,transport,XmltvGuideService())
        val refreshed=service.refresh(session.user.id,saved.id)
        assertTrue(refreshed.available);assertTrue(refreshed.updatedAt>0);assertNull(refreshed.lastError)
        assertEquals("今日新闻",service.guide(session.user.id,saved.id,guideRequest()).channels.single().current?.title)
        assertEquals(429,assertFailsWith<ResponseStatusException> { EpgFeeds(db,transport,XmltvGuideService()).refresh(session.user.id,saved.id) }.statusCode.value())
        db.update("UPDATE epg_feeds SET last_attempt=0 WHERE id=?",saved.id)
        response="<!DOCTYPE tv [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><tv/>"
        val failed=service.refresh(session.user.id,saved.id)
        assertNotNull(failed.lastError);assertEquals(refreshed.updatedAt,failed.updatedAt)
        assertEquals("今日新闻",service.guide(session.user.id,saved.id,guideRequest()).channels.single().current?.title)
    }
    @Test fun concurrentApiInstancesShareOneRefreshLeaseAndDeletingInFlightNeverResurrectsFeed() {
        val owner=user().user.id;val saved=feeds.create(owner,EpgFeedWrite("News","https://example.org/guide"))
        val entered=java.util.concurrent.CountDownLatch(1);val release=java.util.concurrent.CountDownLatch(1)
        val transport=object:ProviderTransport() { override fun get(uri: URI,headers: Map<String,String>,form: String?): String {
            entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS));return xml
        } }
        val first=EpgFeeds(db,transport,XmltvGuideService());val second=EpgFeeds(db,transport,XmltvGuideService())
        java.util.concurrent.Executors.newSingleThreadExecutor().use { pool ->
            val pending=pool.submit<Int> { try { first.refresh(owner,saved.id);200 } catch(e:ResponseStatusException) { e.statusCode.value() } }
            try {
                assertTrue(entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
                assertEquals(429,assertFailsWith<ResponseStatusException> { second.refresh(owner,saved.id) }.statusCode.value())
                feeds.remove(owner,saved.id)
            } finally { release.countDown() }
            assertEquals(404,pending.get(5,java.util.concurrent.TimeUnit.SECONDS));assertTrue(feeds.list(owner).isEmpty())
        }
    }
    @Test fun schedulerHonorsOptInIntervalsAndDeviceRevocation() {
        val active=user();val revoked=user()
        var calls=0
        val transport=object:ProviderTransport() { override fun get(uri: URI,headers: Map<String,String>,form: String?): String { calls++;return xml } }
        val service=EpgFeeds(db,transport,XmltvGuideService())
        val enabled=feeds.create(active.user.id,EpgFeedWrite("Enabled","https://example.org/guide.xml"))
        feeds.create(active.user.id,EpgFeedWrite("Disabled","https://example.org/disabled.xml",enabled=false))
        feeds.create(revoked.user.id,EpgFeedWrite("Revoked","https://example.org/revoked.xml"))
        accounts.revoke(accounts.principal("Bearer "+revoked.token),revoked.device.id)
        service.refreshDue();assertEquals(1,calls)
        assertTrue(service.list(active.user.id).first { it.id==enabled.id }.available)
        service.refreshDue();assertEquals(1,calls)
    }
    @Test fun enforcesCreationQuotasIntervalsAndUnsafeAddressesNeverFetch() {
        val owner=user().user.id
        assertFailsWith<ResponseStatusException> { feeds.create(owner,EpgFeedWrite("Bad","file:///etc/passwd")) }
        assertFailsWith<ResponseStatusException> { feeds.create(owner,EpgFeedWrite("Bad","https://example.org/guide",intervalMinutes=1)) }
        assertFailsWith<ResponseStatusException> { feeds.create(owner,EpgFeedWrite("Bad","https://example.org/"+"a".repeat(2048))) }
        val privateFeed=feeds.create(owner,EpgFeedWrite("Denied","http://127.0.0.1/secret"))
        val result=feeds.refresh(owner,privateFeed.id)
        assertFalse(result.available);assertNotNull(result.lastError)
        repeat(9) { feeds.create(owner,EpgFeedWrite("Feed $it","https://example.org/$it")) }
        assertEquals(409,assertFailsWith<ResponseStatusException> { feeds.create(owner,EpgFeedWrite("Overflow","https://example.org/extra")) }.statusCode.value())
        assertEquals(10,feeds.list(owner).size)
        feeds.remove(owner,privateFeed.id)
        assertEquals(9,feeds.list(owner).size)
    }
    @Test fun simultaneousCreatesCannotExceedPerAccountQuota() {
        val owner=user().user.id
        repeat(9) { feeds.create(owner,EpgFeedWrite("Feed $it","https://example.org/$it")) }
        java.util.concurrent.Executors.newFixedThreadPool(2).use { pool ->
            val results=pool.invokeAll((1..2).map { java.util.concurrent.Callable {
                try { feeds.create(owner,EpgFeedWrite("Concurrent $it","https://example.org/new-$it"));200 }
                catch(e:ResponseStatusException) { e.statusCode.value() }
            } }).map { it.get() }.sorted()
            assertEquals(listOf(200,409),results);assertEquals(10,feeds.list(owner).size)
        }
    }
    @Test fun sharedNativeAndJvmGoldenGuideMatchesSameChannelsAndTimes() {
        val actual=XmltvGuideService().guide(EpgGuideRequest(xml,listOf(EpgChannelRequest("news","News"),EpgChannelRequest("unknown","Unknown")),"2026-10-23T04:30:00Z",12))
        val expected=mapper.readTree(java.nio.file.Files.readString(java.nio.file.Path.of("../../fixtures/p2-epg-guide.json")))
        assertEquals(expected,mapper.valueToTree(actual))
    }
    @Test fun unicodeXmlLimitsAndGzipFilesHaveIndependentCompressedAndDecodedBudgets() {
        assertFailsWith<ResponseStatusException> { XmltvGuideService().validate("<tv><!--"+"中".repeat(700000)+"--></tv>") }
        fun gzip(text: String)=java.io.ByteArrayOutputStream().also { out -> java.util.zip.GZIPOutputStream(out).use { it.write(text.toByteArray()) } }.toByteArray()
        fun response(body: ByteArray)= "HTTP/1.1 200 OK\r\nContent-Length: ${body.size}\r\n\r\n".toByteArray()+body
        assertEquals(xml,ProviderTransport.parseResponse(response(gzip(xml)).inputStream()))
        assertFailsWith<java.io.IOException> { ProviderTransport.parseResponse(response(gzip("a".repeat(ProviderTransport.MAX_BYTES+1))).inputStream()) }
        assertFailsWith<java.io.IOException> { ProviderTransport.parseResponse(response(byteArrayOf(0x1f,0x8b.toByte(),0)).inputStream()) }
    }
}
