package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.*
import org.springframework.http.HttpStatus
import org.springframework.web.server.ResponseStatusException

class AndroidSpiderBridgeTest {
    private val mapper = jacksonObjectMapper()
    private val spec = SpiderSpec("fixture", "csp_Fixture", "https://example.org/worker.jpg;md5;" + "a".repeat(32), "{\"name\":\"测试\"}", listOf("own"))
    private val sid = "12345678-1234-1234-1234-123456789012"
    private fun policy() = SpiderPolicy("http://192.168.50.10:9978", spec.fingerprint())
    private inner class Host : ProviderTransport() {
        val calls = mutableListOf<Triple<String,String,JsonNode?>>()
        val sessions = mutableListOf<Map<String,String>>()
        var failLoad = false
        var malformedResult = false
        var badSession = false
        private var loading = true
        var currentMethod = ""
        val results = mapOf(
            "home" to """{"class":[{"type_id":"movie","type_name":"电影"}]}""",
            "homeVod" to """{"list":[{"vod_id":"v1","vod_name":"Fixture"}]}""",
            "category" to """{"list":[],"pagecount":3}""",
            "search" to """{"list":[],"pagecount":2}""",
            "detail" to """{"list":[{"vod_id":"v1","vod_name":"Fixture","vod_play_from":"line","vod_play_url":"E1${'$'}opaque-id"}]}""",
            "play" to """{"url":"https://cdn.example/own.m3u8","parse":0,"header":{"User-Agent":"Own"}}"""
        )
        override fun bridgeRequest(uri: URI, headers: Map<String,String>, body: String?, method: String, deadline: Long): String {
            assertEquals("192.168.50.10",uri.host)
            assertTrue(headers.keys.all { it == "X-Spider-Session" })
            calls += Triple(method,uri.path,body?.let { mapper.readTree(it) })
            sessions += headers
            return when {
                method == "DELETE" -> "{}"
                uri.path.endsWith("/load") -> { loading=true; """{"state":"loading"}""" }
                uri.path.endsWith("/run") -> {
                    loading=false;currentMethod=mapper.readTree(body).path("method").asText()
                    """{"state":"running"}"""
                }
                method == "GET" -> if (loading) mapper.writeValueAsString(mapOf("state" to if(failLoad) "error" else "loaded","loaded" to !failLoad,"result" to "private stack token"))
                    else mapper.writeValueAsString(mapOf("state" to "done","result" to if(malformedResult) "{} {}" else results[currentMethod]))
                else -> mapper.writeValueAsString(mapOf("session" to if(badSession) "../secret" else sid))
            }
        }
    }
    private fun bridge(host: Host) = AndroidSpiderBridge(mapper,host,policy()).apply { pause={} }

    @Test fun approvedBindingUsesOriginalSessionAndHomePlusHomeVideoContracts() {
        assertEquals("915f90debc5c3d822c2abdf2b64f5ea865c1146f7f5a0ae47a074754204a02f4",spec.fingerprint())
        val host=Host()
        val root=bridge(host).invoke(spec,"home",SiteRequest())
        assertEquals("movie",root.path("class")[0].path("type_id").asText())
        assertEquals("v1",root.path("list")[0].path("vod_id").asText())
        val load=host.calls.single { it.second.endsWith("/load") }.third!!
        assertEquals(spec.api,load.path("api").asText());assertEquals(spec.jar,load.path("jar").asText());assertEquals(spec.ext,load.path("ext").asText())
        assertEquals(listOf("home","homeVod"),host.calls.filter { it.second.endsWith("/run") }.map { it.third!!.path("method").asText() })
        assertEquals("DELETE",host.calls.last().first)
        assertTrue(host.sessions.first().isEmpty());assertEquals(sid,host.sessions.last()["X-Spider-Session"])
    }
    @Test fun categorySearchDetailAndPlayUseOriginalArgumentOrderAndOpaqueIds() {
        val host=Host();val bridge=bridge(host)
        bridge.invoke(spec,"category",SiteRequest(categoryId="movie",page=2,filters=mapOf("year" to "2026")))
        bridge.invoke(spec,"search",SiteRequest(query=" 电影 ",page=3,quick=true))
        bridge.invoke(spec,"detail",SiteRequest(vodId="opaque-id"))
        val play=bridge.invoke(spec,"play",SiteRequest(),mapOf("flag" to "line","play" to "opaque-id"))
        val runs=host.calls.filter { it.second.endsWith("/run") }.map { it.third!!.path("args") }
        assertEquals(mapper.readTree("""["movie","2",true,{"year":"2026"}]"""),runs[0])
        assertEquals(mapper.readTree("""["电影",true,"3"]"""),runs[1])
        assertEquals(mapper.readTree("""[["opaque-id"]]"""),runs[2])
        assertEquals(mapper.readTree("""["line","opaque-id",["own"]]"""),runs[3])
        assertEquals("https://cdn.example/own.m3u8",play.path("url").asText())
        assertEquals(4,host.calls.count { it.first=="DELETE" })
    }
    @Test fun disabledOrChangedInitBindingsCannotContactAndroidHost() {
        val host=Host()
        val disabled=AndroidSpiderBridge(mapper,host,SpiderPolicy())
        assertEquals(422,assertFailsWith<ResponseStatusException> { disabled.invoke(spec,"home",SiteRequest()) }.statusCode.value())
        for (changed in listOf(spec.copy(ext="other"),spec.copy(api="csp_Other"),spec.copy(jar=spec.jar.replace("worker","other")),spec.copy(flags=listOf("other")))) {
            assertFalse(policy().allows(changed))
            assertFailsWith<ResponseStatusException> { bridge(host).invoke(changed,"home",SiteRequest()) }
        }
        assertFailsWith<ResponseStatusException> { bridge(host).invoke(spec,"action",SiteRequest()) }
        assertTrue(host.calls.isEmpty())
    }
    @Test fun loadFailuresAndMalformedResultsAreRedactedAndAlwaysCloseSessions() {
        for (loadFailure in listOf(true,false)) {
            val host=Host().apply { failLoad=loadFailure;malformedResult=!loadFailure }
            val error=assertFailsWith<ResponseStatusException> { bridge(host).invoke(spec,"home",SiteRequest()) }
            assertEquals(HttpStatus.BAD_GATEWAY,error.statusCode)
            assertFalse(error.message.orEmpty().contains("private stack token"))
            assertEquals("DELETE",host.calls.last().first)
        }
    }
    @Test fun deadlineAndInterruptionCannotLeaveAnUnboundedPollingLoop() {
        val host=Host();var clock=0L
        val bridge=bridge(host).apply { nanoTime={clock};pause={clock=16_000_000_000L} }
        assertEquals(504,assertFailsWith<ResponseStatusException> { bridge.invoke(spec,"home",SiteRequest()) }.statusCode.value())
        assertEquals("DELETE",host.calls.last().first)
        host.calls.clear()
        Thread.currentThread().interrupt()
        try {
            assertEquals(408,assertFailsWith<ResponseStatusException> { bridge.invoke(spec,"home",SiteRequest()) }.statusCode.value())
            assertTrue(host.calls.isEmpty())
        } finally { Thread.interrupted() }
    }
    @Test fun untrustedSessionIdentifiersAreNeverReusedAsHeaders() {
        val host=Host().apply { badSession=true }
        assertFailsWith<ResponseStatusException> { bridge(host).invoke(spec,"home",SiteRequest()) }
        assertEquals(1,host.calls.size)
    }
    @Test fun concurrentHostRequestsAreRejectedInsteadOfQueueingUnboundedWork() {
        val entered=CountDownLatch(2);val release=CountDownLatch(1)
        val host=object:ProviderTransport() {
            override fun bridgeRequest(uri: URI,headers: Map<String,String>,body: String?,method: String,deadline: Long): String {
                entered.countDown()
                check(release.await(5,TimeUnit.SECONDS))
                throw java.io.IOException("private host failure")
            }
        }
        val bridge=AndroidSpiderBridge(mapper,host,policy())
        Executors.newFixedThreadPool(2).use { pool ->
            val tasks=(0..1).map { pool.submit<Int> {
                assertFailsWith<ResponseStatusException> { bridge.invoke(spec,"home",SiteRequest()) }.statusCode.value()
            } }
            try {
                assertTrue(entered.await(3,TimeUnit.SECONDS))
                assertEquals(429,assertFailsWith<ResponseStatusException> { bridge.invoke(spec,"home",SiteRequest()) }.statusCode.value())
            } finally { release.countDown() }
            assertEquals(listOf(502,502),tasks.map { it.get(5,TimeUnit.SECONDS) })
        }
        // Failed transports release permits as well as successful invocations.
        assertEquals(502,assertFailsWith<ResponseStatusException> { bridge.invoke(spec,"home",SiteRequest()) }.statusCode.value())
    }
    @Test fun subscribedProviderRoutesApprovedOpaqueEpisodesThroughAndroidInsteadOfHttpApis() {
        val host=Host();val policy=policy()
        val content=mapper.writeValueAsString(mapOf("spider" to spec.jar,"flags" to spec.flags,"sites" to listOf(mapOf("key" to spec.key,"type" to 3,"api" to spec.api,"ext" to mapper.readTree(spec.ext)))))
        val subscriptions=Subscriptions(mapper,host,policy)
        assertEquals("android-spider",subscriptions.load(SubscriptionRequest(content)).sites.single().support)
        val provider=SubscribedProvider(subscriptions,mapper,StaticFongMiProvider(mapper),host,XmlVodAdapter(mapper),bridge(host))
        val request=SiteRequest(content=content,siteKey=spec.key,vodId="v1")
        assertTrue(provider.requiresAuthentication(request))
        assertTrue(provider.detail(request).lines.single().episodes.single().playable)
        assertEquals("https://cdn.example/own.m3u8",provider.play(request).url)
    }
}
