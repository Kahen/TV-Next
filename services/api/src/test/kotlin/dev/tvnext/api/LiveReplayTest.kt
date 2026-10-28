package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.net.URI
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.*
import org.springframework.web.server.ResponseStatusException

class LiveReplayTest {
    private val mapper = jacksonObjectMapper()
    private val golden = mapper.readTree(Files.readString(Path.of("../../fixtures/fongmi-live-replay-golden.json")))
    private val now = golden.path("now").asLong()
    private val time = golden.path("time").asLong()
    private val stop = golden.path("stop").asLong()
    private val shift = mapper.treeToValue(golden.path("timeshift"), LiveTimeshift::class.java)
    private val catchup = mapper.treeToValue(golden.path("catchup"), LiveCatchup::class.java)
    private val live = golden.path("liveUrl").asText()
    private class Transport(var body: String = """{"url":"https://example.org/replay.m3u8","header":{"Cookie":"replay-only"}}""") : ProviderTransport() {
        var called: URI? = null
        var suppliedHeaders: Map<String,String>? = null
        override fun get(uri: URI, headers: Map<String,String>, form: String?): String { called=uri;suppliedHeaders=headers;return body }
    }

    @Test fun originalMillisecondWindowAndZeroLiveSentinel() {
        assertEquals(golden.path("expectedEndpoint").asText(), LiveReplay.timeshiftUrl(shift,time,now))
        assertEquals(golden.path("liveEndpoint").asText(), LiveReplay.timeshiftUrl(shift,0,now))
        assertEquals("https://example.org/?t=$time&again=$time",LiveReplay.timeshiftUrl(shift.copy(url="https://example.org/?t={time}&again=%7bTIME%7d"),time,now))
        listOf(-1L,time-1,now+1,Long.MAX_VALUE).forEach { assertFailsWith<ResponseStatusException> { LiveReplay.timeshiftUrl(shift,it,now) } }
        listOf(shift.copy(start=0),shift.copy(start=now),shift.copy(window=-1),shift.copy(url="https://example.org/no-token"),shift.copy(url="file:///{time}"))
            .forEach { assertFailsWith<ResponseStatusException> { LiveReplay.timeshiftUrl(it,time,now) } }
    }
    @Test fun fetchesResultInsteadOfTreatingRpcAsVideoAndDoesNotInheritStreamSecrets() {
        val transport=Transport()
        val result=LiveReplay(mapper,transport).resolve(LiveReplayRequest(Channel("Live",live,"Live",headers=mapOf("Cookie" to "live-only"),timeshift=shift),time),now)
        assertEquals(golden.path("expectedEndpoint").asText(),transport.called.toString())
        assertTrue(transport.suppliedHeaders!!.isEmpty())
        assertEquals("https://example.org/replay.m3u8",result.url)
        assertEquals(mapOf("Cookie" to "replay-only"),result.headers)
    }
    @Test fun rejectsFailedWebviewDrmAndMalformedTimeshiftResults() {
        listOf("null", "[]", "{}", "{", """{"url":"file:///secret"}""", """{"url":"https://example.org/a","parse":1}""",
            """{"url":"https://example.org/a","jx":1}""", """{"url":"https://example.org/a","msg":"provider secret"}""",
            """{"url":"https://example.org/a","drm":{}}""", """{"url":"https://example.org/a","header":[]}""")
            .forEach { body -> assertFailsWith<ResponseStatusException> { LiveReplay(mapper,Transport(body)).resolve(LiveReplayRequest(Channel("Live",live,"Live",timeshift=shift),time),now) } }
    }
    @Test fun catchupUsesOriginalAppendReplacementAndExplicitTimezone() {
        assertEquals(golden.path("expectedHongKong").asText(),LiveReplay.catchupUrl(live,catchup,time,stop,"Asia/Hong_Kong",now))
        assertEquals(golden.path("expectedUTC").asText(),LiveReplay.catchupUrl(live,catchup.copy(source=catchup.source.replace("yyyyMMddHHmmss}","yyyyMMddHHmmss|UTC}")),time,stop,"Asia/Hong_Kong",now))
        val c=LiveCatchup(type="default",source="https://example.org/replay?b={utc:0}&e={utcend:0}")
        assertEquals("https://example.org/replay?b=${time/1000}&e=${stop/1000}",LiveReplay.catchupUrl(live,c,time,stop,"UTC",now))
    }
    @Test fun dstUsesInstantAndNamedZoneRatherThanServerTimezone() {
        val begin=java.time.Instant.parse("2026-11-01T05:30:00Z").toEpochMilli()
        val end=begin+3_600_000
        val c=LiveCatchup(source="?from=${'$'}{(b)yyyyMMddHHmmss}&to=${'$'}{(e)yyyyMMddHHmmss}")
        assertEquals("https://example.org/live?from=20261101013000&to=20261101013000",LiveReplay.catchupUrl("https://example.org/live",c,begin,end,"America/New_York",end))
        assertEquals("https://example.org/live?from=20261101053000&to=20261101063000",LiveReplay.catchupUrl("https://example.org/live",c.copy(source=c.source.replace("yyyyMMddHHmmss}","yyyyMMddHHmmss|UTC}")),begin,end,"America/New_York",end))
    }
    @Test fun rejectsUnsupportedTemplatesCrossOriginAndUnboundedPrograms() {
        listOf(catchup.copy(type="shift"),catchup.copy(days="0"),catchup.copy(days="999999999999"),catchup.copy(regex="(a+)+"),
            catchup.copy(source="?begin={unknown}"),catchup.copy(source="?begin=%7Btime%7D"),catchup.copy(source="?begin=${'$'}{(b)invalid}"),
            catchup.copy(type="default",source="https://attacker.invalid/?b={utc:0}"),catchup.copy(replace="/PLTV/,[bad"))
            .forEach { assertFailsWith<ResponseStatusException> { LiveReplay.catchupUrl(live,it,time,stop,"UTC",now) } }
        listOf(0L to stop,(now-31L*86_400_000) to stop,time to time,time to now+1,Long.MIN_VALUE to stop).forEach { (b,e) ->
            assertFailsWith<ResponseStatusException> { LiveReplay.catchupUrl(live,catchup,b,e,"UTC",now) }
        }
        assertFailsWith<ResponseStatusException> { LiveReplay.catchupUrl(live,catchup,time,stop,"bad/timezone",now) }
    }
    @Test fun programmeCatchupDoesNotCallTimeshiftRpc() {
        val transport=Transport()
        val result=LiveReplay(mapper,transport).resolve(LiveReplayRequest(Channel("Live",live,"Live",timeshift=shift,catchup=catchup),time,stop,"Asia/Hong_Kong"),now)
        assertNull(transport.called);assertEquals(golden.path("expectedHongKong").asText(),result.url)
    }
    @Test fun m3uAndNestedJsonRetainCatchupAndTimeshiftWithoutCrossChannelBleed() {
        val m3u=PlaylistParser().parse("#EXTM3U catchup=\"append\" catchup-source=\"?b={utc:0}\"\n#EXTINF:-1,One\nhttps://example.org/a\n#EXTINF:-1 catchup=\"default\" catchup-source=\"https://example.org/b?time={utc:0}\",Two\nhttps://example.org/b\n#EXTINF:-1,Three\nhttps://example.org/c")
        assertEquals("append",m3u.channels[0].catchup?.type);assertEquals("default",m3u.channels[1].catchup?.type);assertEquals("append",m3u.channels[2].catchup?.type)
        val transport=Transport();val service=LiveSubscriptions(mapper,Subscriptions(mapper,transport),transport,PlaylistParser())
        val channel=mapper.createObjectNode().put("name","One").put("tvgId","news").set<com.fasterxml.jackson.databind.node.ObjectNode>("timeshift",golden.path("timeshift"))
        channel.putArray("urls").add("https://example.org/a")
        val group=mapper.createObjectNode().put("name","News");group.putArray("channel").add(channel)
        val live=mapper.createObjectNode();live.set<com.fasterxml.jackson.databind.node.ObjectNode>("catchup",golden.path("catchup"));live.putArray("groups").add(group)
        val root=mapper.createObjectNode();root.putArray("lives").add(live)
        val parsed=service.load(LiveImportRequest(root.toString())).channels.single()
        assertEquals(shift,parsed.timeshift);assertEquals(catchup,parsed.catchup);assertEquals("news",parsed.tvgId)
    }
    @Test fun epgHistoryIsBoundedAndRemainsDistinctFromUpcoming() {
        val xml="""<tv><channel id="n"><display-name>News</display-name></channel><programme channel="n" start="20261025070000 +0000" stop="20261025073000 +0000"><title>Replay</title></programme></tv>"""
        val service=XmltvGuideService();val request=EpgGuideRequest(xml,listOf(EpgChannelRequest("n","News")),"2026-10-25T08:00:00Z")
        assertTrue(service.guide(request).channels[0].previous.isEmpty())
        val guide=service.guide(request.copy(pastHours=1)).channels[0]
        assertEquals("Replay",guide.previous.single().title);assertNull(guide.current);assertTrue(guide.upcoming.isEmpty())
        assertFailsWith<ResponseStatusException> { service.guide(request.copy(pastHours=169)) }
    }
}
