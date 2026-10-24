package dev.tvnext.api

import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URI
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.*
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.context.TestConfiguration
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Primary
import org.springframework.http.HttpStatus
import org.springframework.web.server.ResponseStatusException

@SpringBootTest(properties=["TV_NEXT_REGISTRATION_OPEN=true"])
class ProviderGatewayTest @Autowired constructor(private val accounts: HomeAccounts,private val gateway: ProviderGateway,
    private val transport: FixtureTransport,private val mapper: ObjectMapper) {
    class FixtureTransport: ProviderTransport() {
        val calls=AtomicInteger()
        @Volatile var blocked: Pair<CountDownLatch,CountDownLatch>?=null
        override fun get(uri: URI,headers: Map<String,String>,form: String?): String {
            val count=calls.incrementAndGet()
            blocked?.let { it.first.countDown();check(it.second.await(5,TimeUnit.SECONDS)) }
            if(uri.host=="failure.example")throw ResponseStatusException(HttpStatus.BAD_GATEWAY,"secret upstream URL/cookie/query")
            return """{"list":[{"vod_id":"$count","vod_name":"Fixture"}],"total":1}"""
        }
    }
    @TestConfiguration class Config { @Bean @Primary fun fixtureTransport()=FixtureTransport() }
    private fun user()=accounts.register(Credentials("provider-"+UUID.randomUUID(),"long-test-password","Source device"))
    private fun request(host: String="source.example")=SiteRequest(content="""{"sites":[{"key":"owned","type":1,"api":"https://$host/api?token=private-source","header":{"Cookie":"private-cookie"}}]}""",siteKey="owned",query="private-query")
    @Test fun cacheIsDevicePrivateExpiresAndSupportsExplicitRefreshAndClear() {
        val one=user();val two=user();val auth="Bearer "+one.token;val r=request();val before=transport.calls.get()
        val first=gateway.page("search",r,auth)
        assertEquals(first,gateway.page("search",r,auth));assertEquals(before+1,transport.calls.get())
        gateway.page("search",r,"Bearer "+two.token);assertEquals(before+2,transport.calls.get())
        gateway.page("search",r.copy(bypassCache=true),auth);assertEquals(before+3,transport.calls.get())
        val original=gateway.now
        try { val time=System.currentTimeMillis()+61_000;gateway.now={time};gateway.page("search",r,auth);assertEquals(before+4,transport.calls.get()) }
        finally { gateway.now=original }
        val p=accounts.principal(auth);gateway.clear(p);assertTrue(gateway.list(p).isEmpty())
        gateway.page("search",r,auth);assertEquals(before+5,transport.calls.get())
        assertEquals(1,gateway.list(p).single().networkCalls)
    }
    @Test fun deviceEntryQuotaEvictsOldSearchesAndAnonymousRequestsStayUncached() {
        val user=user();val auth="Bearer "+user.token;val before=transport.calls.get()
        repeat(17) { gateway.page("search",request().copy(query="query-$it"),auth) }
        gateway.page("search",request().copy(query="query-0"),auth)
        assertEquals(before+18,transport.calls.get())
        repeat(2) { gateway.page("search",request(),null) }
        assertEquals(before+20,transport.calls.get())
    }
    @Test fun failuresAreNotCachedAndHealthNeverIncludesSourceCredentialsOrQueries() {
        val user=user();val auth="Bearer "+user.token;val p=accounts.principal(auth)
        repeat(2) { assertFailsWith<ResponseStatusException> { gateway.page("search",request("failure.example"),auth) } }
        val health=gateway.list(p).single();assertEquals(2,health.failures);assertEquals("upstream-failure",health.lastError)
        val json=mapper.writeValueAsString(health)
        listOf("private-source","private-cookie","private-query","failure.example",user.token).forEach { assertFalse(json.contains(it)) }
        assertFailsWith<ResponseStatusException> { gateway.page("search",request(),"Bearer invalid") }
        accounts.revoke(p,user.device.id);assertTrue(gateway.list(p).isEmpty())
        assertFailsWith<ResponseStatusException> { gateway.page("search",request(),auth) }
    }
    @Test fun clearingWhileARequestIsRunningCannotRepopulateItsCacheOrHealth() {
        val user=user();val auth="Bearer "+user.token;val p=accounts.principal(auth);val enter=CountDownLatch(1);val release=CountDownLatch(1)
        transport.blocked=enter to release
        try {
            java.util.concurrent.Executors.newSingleThreadExecutor().use { pool ->
                val pending=pool.submit<ProviderPage> { gateway.page("search",request(),auth) }
                assertTrue(enter.await(5,TimeUnit.SECONDS));gateway.clear(p);release.countDown();pending.get(5,TimeUnit.SECONDS)
            }
        } finally { release.countDown();transport.blocked=null }
        assertTrue(gateway.list(p).isEmpty());val calls=transport.calls.get()
        gateway.page("search",request(),auth);assertEquals(calls+1,transport.calls.get())
    }
}
