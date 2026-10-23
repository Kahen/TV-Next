package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.net.InetAddress
import java.net.URI
import java.util.Base64
import kotlin.test.*
import org.springframework.web.server.ResponseStatusException

class SubscriptionCompatibilityTest {
    private val mapper = jacksonObjectMapper()
    private class FakeTransport : ProviderTransport() {
        var answer = "{}"
        var uri: URI? = null
        var headers = emptyMap<String, String>()
        var form: String? = null
        override fun get(uri: URI, headers: Map<String, String>, form: String?): String {
            this.uri = uri; this.headers = headers; this.form = form; return answer
        }
    }
    private val transport = FakeTransport()
    private val subscriptions = Subscriptions(mapper, transport)
    private val provider = SubscribedProvider(subscriptions, mapper, StaticFongMiProvider(mapper), transport, XmlVodAdapter(mapper))
    private val config = """{"spider":"./spider.jar;md5;abc","sites":[{"key":"pan","name":"Cloud HTTP Spider","type":4,"api":"https://provider.example/api?token=own","ext":{"token":"own"},"header":{"Referer":"https://provider.example/"}},{"key":"android","type":3,"api":"csp_Cloud","ext":["a","b"]}],"urls":[{"name":"Next","url":"../next.json"}],"lives":[{"url":"./live.txt"}],"parses":[{"url":"https://example.org/?url="}],"unknown":{"keep":true}}"""

    @Test fun retainsUpstreamFieldsAndRelativePaths() {
        val doc = subscriptions.load(SubscriptionRequest(config, "https://example.org/a/config.json"))
        val site = doc.sites[0]
        assertEquals("https://example.org/a/spider.jar;md5;abc", site.jar)
        assertEquals("{\"token\":\"own\"}", site.ext)
        assertTrue(site.searchable); assertTrue(site.quickSearch); assertTrue(site.changeable)
        assertEquals("https://example.org/next.json", doc.depots.single().url)
        assertTrue(mapper.readTree(doc.content).path("unknown").path("keep").asBoolean())
        assertEquals("[\"a\",\"b\"]", doc.sites[1].ext)
        assertEquals("requires-spider-runtime", doc.sites[1].support)
    }
    @Test fun decodesOriginalBase64WrapperAndRejectsMalformedInputs() {
        val encoded = "abcdefgh**" + Base64.getEncoder().encodeToString(config.toByteArray())
        assertEquals(subscriptions.load(SubscriptionRequest(config)).sites, subscriptions.load(SubscriptionRequest(encoded)).sites)
        assertFailsWith<ResponseStatusException> { subscriptions.load(SubscriptionRequest("2423nothex")) }
        assertFailsWith<ResponseStatusException> { subscriptions.load(SubscriptionRequest("😀".repeat(300_000))) }
    }
    @Test fun originalAesEnvelopeAndLongCloudFolderIdRoundTrip() {
        val key = "testkey".padEnd(16,'0').toByteArray()
        val ivText = "1234567890123"
        val cipher = javax.crypto.Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(javax.crypto.Cipher.ENCRYPT_MODE,javax.crypto.spec.SecretKeySpec(key,"AES"),javax.crypto.spec.IvParameterSpec(ivText.padEnd(16,'0').toByteArray()))
        fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
        val envelope = hex("${'$'}#testkey#${'$'}".toByteArray()) + hex(cipher.doFinal(config.toByteArray())) + hex(ivText.toByteArray())
        assertEquals(subscriptions.load(SubscriptionRequest(config)).sites, subscriptions.load(SubscriptionRequest(envelope)).sites)
        val id = "cloud-folder:" + "a".repeat(1000)
        val data = StaticFongMiProvider(mapper).read("""{"list":[{"vod_id":"$id","vod_name":"Folder","vod_tag":"folder"}]}""",true)
        assertEquals(id,data.entries.single().item.id)
        assertTrue(data.entries.single().item.folder)
    }
    @Test fun originalSiteApiParameterConventions() {
        assertEquals(mapOf("filter" to "true"), provider.params(4, "home", SiteRequest(), ""))
        assertEquals(emptyMap(), provider.params(1, "home", SiteRequest(), ""))
        val search = provider.params(4, "search", SiteRequest(query="电影", page=1), "")
        assertEquals(mapOf("wd" to "电影", "quick" to "false", "extend" to ""), search)
        assertFalse("ac" in search); assertFalse("pg" in search)
        val category = provider.params(0, "category", SiteRequest(categoryId="1",page=2), "")
        assertEquals("videolist", category["ac"])
        val filter = provider.params(4,"category",SiteRequest(categoryId="1",filters=mapOf("year" to "2026")),"")
        assertEquals("{\"year\":\"2026\"}", String(Base64.getUrlDecoder().decode(filter.getValue("ext"))))
    }
    @Test fun httpSpiderResolvesOpaqueCloudIdsAndCarriesDanmakuSubsAndHeaders() {
        transport.answer = """{"list":[{"vod_id":"v1","vod_name":"Movie","vod_play_from":"Cloud","vod_play_url":"E1${'$'}opaque-share*file-id"}]}"""
        val request = SiteRequest(content=config,siteKey="pan",vodId="v1")
        assertTrue(provider.detail(request).lines.single().episodes.single().playable)
        assertEquals("https://provider.example/", transport.headers["Referer"])
        transport.answer = """{"url":"https://cdn.example/movie.mp4","parse":0,"header":{"User-Agent":"OwnPlayer"},"danmaku":"[{\"name\":\"弹幕\",\"url\":\"https://cdn.example/dm.xml\"}]","subs":[{"name":"中文","url":"https://cdn.example/s.vtt","lang":"zh"}]}"""
        // Playback makes detail then play calls; return separate responses per operation.
        val switching = object : ProviderTransport() {
            override fun get(uri: URI, headers: Map<String,String>, form: String?) = if (uri.rawQuery.contains("play=")) transport.answer else
                """{"list":[{"vod_id":"v1","vod_name":"Movie","vod_play_from":"Cloud","vod_play_url":"E1${'$'}opaque-share*file-id"}]}"""
        }
        val service = SubscribedProvider(subscriptions, mapper, StaticFongMiProvider(mapper), switching, XmlVodAdapter(mapper))
        val play = service.play(request)
        assertEquals("https://cdn.example/movie.mp4", play.url)
        assertEquals("OwnPlayer",play.headers["User-Agent"])
        assertEquals("https://cdn.example/dm.xml",play.danmaku.single().url)
        assertEquals("zh",play.subtitles.single().lang)
    }
    @Test fun xmlTypeZeroUsesOriginalVodMappingAndRejectsEntities() {
        val xml = """<rss><class><ty id="1">电影</ty></class><list page="2" pagecount="3" pagesize="20" recordcount="45"><video><id>v1</id><name>Movie</name><dl><dd flag="line"><![CDATA[E1${'$'}https://example.org/a.mp4#E2${'$'}https://example.org/b.mp4]]></dd></dl></video></list></rss>"""
        val data = XmlVodAdapter(mapper).parse(xml)
        assertEquals("45", data.path("total").asText())
        val parsed = StaticFongMiProvider(mapper).read(data.toString())
        assertEquals(2,parsed.entries.single().lines.single().episodes.size)
        assertFailsWith<ResponseStatusException> { XmlVodAdapter(mapper).parse("""<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]><rss/>""") }
    }
    @Test fun blocksNonPublicAddressesAndHeaderInjection() {
        listOf("127.0.0.1","10.0.0.1","169.254.169.254","100.64.1.1","192.168.1.1","::1","fc00::1","2001:db8::1","::ffff:127.0.0.1").forEach {
            assertFalse(ProviderTransport.publicAddress(InetAddress.getByName(it)), it)
        }
        assertTrue(ProviderTransport.publicAddress(InetAddress.getByName("8.8.8.8")))
        assertFailsWith<ResponseStatusException> { ProviderTransport.validateHeaders(mapOf("Host" to "127.0.0.1")) }
        assertFailsWith<ResponseStatusException> { ProviderTransport.validateHeaders(mapOf("Referer" to "x\r\nHost: x")) }
    }
    @Test fun boundedHttpHandlesChunksAndRejectsRedirectsAmbiguityAndBombs() {
        assertEquals("{}",ProviderTransport.parseResponse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n".byteInputStream()))
        listOf("HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1/\r\n\r\n", "HTTP/1.1 200 OK\r\nContent-Length: 1048577\r\n\r\n", "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n").forEach {
            assertFails { ProviderTransport.parseResponse(it.byteInputStream()) }
        }
    }
}
