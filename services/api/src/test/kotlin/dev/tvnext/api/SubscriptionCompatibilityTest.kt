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
    @Test fun imageEnvelopeAndCommentedConfigLoadLikeOriginalDecoder() {
        val commented = """{
            // Subscription comments accepted by upstream Gson
            "spider":"./worker.jpg;md5;0123456789abcdef0123456789abcdef",
            "sites":[/* keep https:// inside strings */{"key":"fixture","type":3,"api":"csp_Fixture","ext":{"url":"https://example.org/x//y"}}]
        }"""
        val body = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 0xe0.toByte()) +
            ("abcdefgh**" + Base64.getEncoder().encodeToString(commented.toByteArray())).toByteArray()
        val wire = "HTTP/1.1 200 OK\r\nContent-Type: image/x-ms-bmp\r\nContent-Length: ${body.size}\r\n\r\n".toByteArray() + body
        val fetched = object : ProviderTransport() {
            override fun getDocument(uri: URI, headers: Map<String,String>): FetchedText {
                assertEquals("www.xn--sss604efuw.net", uri.host)
                return FetchedText(ProviderTransport.parseResponse(wire.inputStream(), true), URI("https://cdn.example/path/config"))
            }
        }
        val document = Subscriptions(mapper,fetched).load(SubscriptionRequest(url="http://www.饭太硬.net/tv"))
        assertEquals(1, document.sites.size)
        assertEquals("https://cdn.example/path/worker.jpg;md5;0123456789abcdef0123456789abcdef", document.sites.single().jar)
        assertEquals("https://example.org/x//y", mapper.readTree(document.content).path("sites")[0].path("ext").path("url").asText())
        assertEquals("requires-spider-runtime", document.sites.single().support)
        assertFails { ProviderTransport.parseResponse(wire.inputStream()) }
        assertFailsWith<ResponseStatusException> { subscriptions.load(SubscriptionRequest(commented + " {}")) }
        // The compatibility reader must not relax the shared JSON mapper.
        assertFails { mapper.readTree(commented) }
    }
    @Test fun unicodeDomainsNormalizeWithoutChangingSignedPathsOrWeakeningAuthorityValidation() {
        assertEquals("http://www.xn--sss604efuw.net/tv?x=%2F&x=+", Subscriptions.httpUri("http://www.饭太硬.net/tv?x=%2F&x=+").toString())
        assertEquals("https://xn--fsqu00a.xn--0zwm56d:8443/a%2Fb?q=%E4%B8%AD", Subscriptions.httpUri("HTTPS://例子.测试:8443/a%2Fb?q=%E4%B8%AD").toString())
        assertEquals("http://[2001:4860:4860::8888]:8080/a", Subscriptions.httpUri("http://[2001:4860:4860::8888]:8080/a").toString())
        listOf("http://用户:密码@饭太硬.net/tv", "http://饭太硬.net@127.0.0.1/", "http://%31%32%37.0.0.1/",
            "http://饭太硬.net:/", "http://饭太硬.net:0/", "http://饭太硬.net:65536/", "http://饭太硬.net:bad/",
            "http://bad_host.example/", "http://饭太硬.net\\@127.0.0.1/", "http://饭太硬.net/#x", "http://[fe80::1%25eth0]/").forEach {
            assertFailsWith<ResponseStatusException>(it) { Subscriptions.httpUri(it) }
        }
    }
    @Test fun envelopesDoNotMaskInvalidUtf8OrArbitrarySuffixBytes() {
        fun wire(body: ByteArray) = "HTTP/1.1 200 OK\r\nContent-Length: ${body.size}\r\n\r\n".toByteArray() + body
        assertFails { ProviderTransport.parseResponse(wire(byteArrayOf(0xff.toByte()) + "abcdefgh**e30=!".toByteArray()).inputStream(), true) }
        assertFails { ProviderTransport.parseResponse(wire(byteArrayOf(0xff.toByte()) + "not an envelope".toByteArray()).inputStream(), true) }
        assertFailsWith<ResponseStatusException> { subscriptions.load(SubscriptionRequest("abcdefgh**e30=!")) }
        assertFailsWith<ResponseStatusException> { subscriptions.load(SubscriptionRequest("abcdefgh**" + Base64.getEncoder().encodeToString(byteArrayOf(0xff.toByte())))) }
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
    @Test fun largeUpstreamPagesAreNotTruncatedOrRepaginatedLocally() {
        val root=mapper.createObjectNode().put("pagecount",2).put("total",300).put("limit",150)
        val list=root.putArray("list")
        repeat(150) { list.addObject().put("vod_id",it.toString()).put("vod_name","Video $it") }
        transport.answer=root.toString()
        val result=provider.page("home",SiteRequest(content=config,siteKey="pan"))
        assertEquals(150,result.items.size);assertEquals("149",result.items.last().id)
        assertEquals(150,result.pageSize);assertTrue(result.hasMore)
    }
    @Test fun repeatableResponseHeadersAreAcceptedWhileFramingStaysUnambiguous() {
        assertEquals("{}",ProviderTransport.parseResponse("HTTP/1.1 200 OK\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\nVary: Accept\r\nVary: Accept-Encoding\r\nContent-Length: 2\r\n\r\n{}".byteInputStream()))
        assertFails { ProviderTransport.parseResponse("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}".byteInputStream()) }
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
