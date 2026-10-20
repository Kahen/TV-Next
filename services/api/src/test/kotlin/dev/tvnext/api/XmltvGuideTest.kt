package dev.tvnext.api

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.springframework.http.HttpStatus
import org.springframework.web.server.ResponseStatusException

class XmltvGuideTest {
    private val service = XmltvGuideService()

    private val xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="news.hk"><display-name lang="zh">CCTV 新闻</display-name><display-name>News HD</display-name></channel>
          <channel id="sports.jp"><display-name>Sports</display-name></channel>
          <programme channel="news.hk" start="20261020190000 +0800" stop="20261020200000 +0800">
            <title lang="zh">今日新闻</title><desc>重点节目</desc>
          </programme>
          <programme channel="news.hk" start="20261020200000 +0800" stop="20261020210000 +0800">
            <title>晚间报道</title>
          </programme>
          <programme channel="sports.jp" start="20261020203000 +0900" stop="20261020210000 +0900">
            <title>赛事转播</title>
          </programme>
          <programme channel="news.hk" start="BAD DATE" stop="20261020223000 +0800"><title>无效时间</title></programme>
        </tv>
    """.trimIndent()

    @Test
    fun prefersIdThenUniqueDisplayNameAndMatchesTimezones() {
        val result = service.guide(EpgGuideRequest(
            xml = xml,
            channels = listOf(
                EpgChannelRequest("news.hk", "Wrong name"),
                EpgChannelRequest(name = " SPORTS "),
                EpgChannelRequest("wrong.id", "Unknown")
            ),
            at = "2026-10-20T11:30:00Z",
            hours = 3
        ))
        assertEquals(3, result.totalChannels)
        assertEquals(2, result.matchedChannels)
        assertEquals("id", result.channels[0].matchType)
        assertEquals("今日新闻", result.channels[0].current?.title)
        assertEquals("2026-10-20T11:00:00Z", result.channels[0].current?.start)
        assertEquals("晚间报道", result.channels[0].upcoming.single().title)
        assertEquals("name", result.channels[1].matchType)
        assertEquals("sports.jp", result.channels[1].matchedChannelId)
        assertEquals("赛事转播", result.channels[1].current?.title)
        assertEquals("none", result.channels[2].matchType)
        assertNull(result.channels[2].current)
    }

    @Test
    fun parsesShortTimestampsAndUtcDefault() {
        val result = service.guide(EpgGuideRequest(
            xml = """<tv><channel id="c"><display-name>C</display-name></channel>
                <programme start="202610201200" stop="202610201300" channel="c"><title>Live</title></programme></tv>""",
            channels = listOf(EpgChannelRequest("c", "C")),
            at = "2026-10-20T12:10:00+00:00"
        ))
        assertEquals("Live", result.channels.single().current?.title)
    }

    @Test
    fun ambiguousDisplayNamesDoNotAssociateWrongChannels() {
        val feed = """<tv><channel id="a"><display-name>Same</display-name></channel>
          <channel id="b"><display-name> SAME </display-name></channel>
          <programme channel="a" start="20261020120000 +0000" stop="20261020130000 +0000"><title>A</title></programme></tv>"""
        val result = service.guide(EpgGuideRequest(
            xml=feed, channels=listOf(EpgChannelRequest(name="Same")),
            at="2026-10-20T12:20:00Z"
        ))
        assertEquals("none", result.channels.single().matchType)
    }

    @Test
    fun rejectsDoctypeAndExternalEntitiesWithoutReadingAnything() {
        val malicious = """<?xml version="1.0"?>
        <!DOCTYPE tv [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
        <tv><channel id="a"><display-name>&xxe;</display-name></channel></tv>"""
        assertEquals(HttpStatus.BAD_REQUEST, assertFailsWith<ResponseStatusException> {
            service.guide(EpgGuideRequest(xml=malicious, channels=listOf(EpgChannelRequest(name="a"))))
        }.statusCode)
    }

    @Test
    fun rejectsMalformedXmlTimeHorizonAndOversizeInputs() {
        val channel = listOf(EpgChannelRequest("c", "C"))
        val badRequests = listOf(
            EpgGuideRequest("<tv>", channel),
            EpgGuideRequest(xml, channel, hours=0),
            EpgGuideRequest(xml, channel, hours=73),
            EpgGuideRequest(xml, channel, at="2026-10-20"),
            EpgGuideRequest(xml, emptyList()),
            EpgGuideRequest("x".repeat(2_097_153), channel)
        )
        badRequests.forEach {
            assertEquals(HttpStatus.BAD_REQUEST, assertFailsWith<ResponseStatusException> {
                service.guide(it)
            }.statusCode)
        }
    }

    @Test
    fun excludesPastAndBeyondHorizonUpcomingAndLimitsResults() {
        val result = service.guide(EpgGuideRequest(xml, listOf(EpgChannelRequest("news.hk", "News")),
            at="2026-10-20T11:30:00Z",hours=1))
        assertTrue(result.channels.single().upcoming.isNotEmpty())
        assertEquals("晚间报道", result.channels.single().upcoming.single().title)
    }
}
