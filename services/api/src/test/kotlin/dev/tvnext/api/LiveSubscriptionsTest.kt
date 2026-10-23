package dev.tvnext.api
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import kotlin.test.*
import org.springframework.web.server.ResponseStatusException
class LiveSubscriptionsTest {
    private val mapper=jacksonObjectMapper()
    private val transport=ProviderTransport()
    private val service=LiveSubscriptions(mapper,Subscriptions(mapper,transport),transport,PlaylistParser())
    @Test fun originalGenreTxtAndMultiUrls() {
        val result=service.load(LiveImportRequest("News,#genre#\nChannel,https://example.org/a#https://example.org/b\nOther,#genre#\nSecond,https://example.org/c|Referer=x"))
        assertEquals(3,result.total);assertEquals(listOf("News","News","Other"),result.channels.map { it.group })
        assertTrue(result.warnings.isNotEmpty())
    }
    @Test fun originalNestedGroupJsonAndPlainM3u() {
        val content="""{"lives":[{"name":"IPTV","groups":[{"name":"News","channel":[{"name":"One","urls":["https://example.org/live","rtsp://example.org/live"]}]}]}]}"""
        val result=service.load(LiveImportRequest(content))
        assertEquals(1,result.total);assertTrue(result.warnings.isNotEmpty())
        assertEquals("One",service.load(LiveImportRequest("#EXTM3U\n#EXTINF:-1,One\nhttps://example.org/live")).channels.single().name)
        assertFailsWith<ResponseStatusException> { service.load(LiveImportRequest("x".repeat(1_048_577))) }
    }
}
