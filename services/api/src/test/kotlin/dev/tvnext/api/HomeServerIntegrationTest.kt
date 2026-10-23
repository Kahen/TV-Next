package dev.tvnext.api

import com.fasterxml.jackson.databind.ObjectMapper
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlin.test.*
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status
import org.springframework.web.server.ResponseStatusException

@SpringBootTest(properties=["spring.datasource.url=\${TV_NEXT_TEST_DB_URL:jdbc:h2:mem:home-tests;DB_CLOSE_DELAY=-1}","TV_NEXT_REGISTRATION_OPEN=true"])
@AutoConfigureMockMvc
class HomeServerIntegrationTest @Autowired constructor(private val accounts: HomeAccounts,private val library: LibrarySync,
    private val db: JdbcTemplate,private val mapper: ObjectMapper,private val mvc: MockMvc) {
    private fun user()=accounts.register(Credentials("user-"+UUID.randomUUID().toString(),"long-test-password","Test device"))
    private fun principal(session: HomeSession)=accounts.principal("Bearer "+session.token)
    private fun snapshot(name: String="Own")=mapper.readTree("""{"version":1,"channels":[{"name":"$name","url":"https://example.org/movie.mp4","group":"Own","headers":{"Cookie":"private-cookie","User-Agent":"TV-Next"}}],"favorites":["https://example.org/movie.mp4"],"recent":[{"channel":{"name":"Own","url":"https://example.org/movie.mp4","group":"Own"},"openedAt":1}],"positions":{"https://example.org/movie.mp4":45}}""")
    @Test fun storesOnlyPasswordAndTokenHashesAndScopesAllLibrariesToUser() {
        val one=user();val two=user();val a=principal(one);val b=principal(two)
        assertNotEquals(one.token,db.queryForObject("SELECT token_hash FROM devices WHERE id=?",String::class.java,one.device.id))
        val saved=library.save(a,SaveLibraryRequest(0,snapshot()))
        assertEquals(1,saved.revision);assertTrue(saved.library.path("channels")[0].path("headersRequired").asBoolean())
        assertFalse(saved.library.toString().contains("private-cookie"))
        assertTrue(library.read(b).library.path("channels").isEmpty)
        assertEquals(0,library.read(b).revision)
        assertFailsWith<ResponseStatusException> { accounts.revoke(a,two.device.id) }
        assertEquals(b,principal(two))
    }
    @Test fun pairingCodesAreSingleUseExpireAndRevocationInvalidatesAccess() {
        val session=user();val p=principal(session)
        val code=accounts.pairing(p)
        val paired=accounts.claim(PairingRequest("New iPad",code.code))
        assertEquals(session.user.id,paired.user.id)
        assertNotEquals(session.token,paired.token)
        assertEquals(2,accounts.devices(p).size)
        assertFailsWith<ResponseStatusException> { accounts.claim(PairingRequest("Replay",code.code)) }
        val expired=accounts.pairing(p)
        db.update("UPDATE device_pairings SET expires_at=0 WHERE creator_device=?",p.deviceId)
        assertFailsWith<ResponseStatusException> { accounts.claim(PairingRequest("Expired",expired.code)) }
        accounts.revoke(p,paired.device.id)
        assertFailsWith<ResponseStatusException> { principal(paired) }
        assertEquals(p,principal(session))
    }
    @Test fun compareAndSetPreventsConcurrentHistoryOverwriteAndDataSurvivesFreshServiceInstances() {
        val session=user();val p=principal(session)
        val results=Executors.newFixedThreadPool(2).use { pool ->
            pool.invokeAll(listOf("A","B").map { name -> Callable {
                try { library.save(p,SaveLibraryRequest(0,snapshot(name)));200 }
                catch(e: ResponseStatusException){e.statusCode.value()}
            } }).map { it.get() }
        }
        assertEquals(listOf(200,409),results.sorted())
        val fresh=LibrarySync(db,mapper).read(p)
        assertEquals(1,fresh.revision);assertEquals(45.0,fresh.library.path("positions").path("https://example.org/movie.mp4").asDouble())
    }
    @Test fun rejectsInvalidSnapshotAndDisabledRegistrationWithoutChangingPreviousData() {
        val session=user();val p=principal(session)
        assertFailsWith<ResponseStatusException> { library.save(p,SaveLibraryRequest(0,mapper.readTree("{}"))) }
        val bad=snapshot() as com.fasterxml.jackson.databind.node.ObjectNode
        (bad.path("channels")[0] as com.fasterxml.jackson.databind.node.ObjectNode).put("url","javascript:alert(1)")
        assertFailsWith<ResponseStatusException> { library.save(p,SaveLibraryRequest(0,bad)) }
        assertEquals(0,library.read(p).revision)
        assertFailsWith<ResponseStatusException> { HomeAccounts(db,false,org.springframework.context.ApplicationEventPublisher { }).register(Credentials("new-user","long-test-password")) }
        assertFailsWith<ResponseStatusException> { accounts.login(Credentials(session.user.username,"wrong-password")) }
    }
    @Test fun passwordLoginRecoversAtDeviceQuotaWithoutLettingPairingEvictDevices() {
        val first=user();val p=principal(first)
        val pairing=accounts.pairing(p)
        repeat(49) { index ->
            db.update("INSERT INTO devices(id,user_id,name,token_hash,created_at,expires_at,revoked) VALUES(?,?,?,?,?,?,FALSE)",
                UUID.randomUUID().toString(),first.user.id,"Fixture",
                ("fixture-"+first.user.id+"-"+index.toString().padStart(4,'0')).padEnd(64,'x'),System.currentTimeMillis()+1000+index,first.device.expiresAt)
        }
        assertEquals(50,accounts.devices(p).size)
        assertEquals(409,assertFailsWith<ResponseStatusException> { accounts.claim(PairingRequest("At quota",pairing.code)) }.statusCode.value())
        assertEquals(50,accounts.devices(p).size)
        val recovered=accounts.login(Credentials(first.user.username,"long-test-password","Recovered"))
        assertEquals(50,accounts.devices(principal(recovered)).size)
        assertFailsWith<ResponseStatusException> { principal(first) }
        assertFailsWith<ResponseStatusException> { accounts.claim(PairingRequest("Revoked creator",pairing.code)) }
    }
    @Test fun httpContractRequiresBearerAndNeverAcceptsCallerChosenUserId() {
        mvc.perform(get("/api/v1/home/library")).andExpect(status().isUnauthorized)
        mvc.perform(get("/api/v1/home/diagnostics")).andExpect(status().isUnauthorized)
        val one=user();val two=user()
        val payload=mapper.createObjectNode().put("expectedRevision",0).put("userId",one.user.id).set<com.fasterxml.jackson.databind.JsonNode>("library",snapshot())
        mvc.perform(post("/api/v1/home/library").header("Authorization","Bearer "+two.token).contentType(MediaType.APPLICATION_JSON).content(mapper.writeValueAsBytes(payload))).andExpect(status().isOk)
        val diagnostic=mvc.perform(get("/api/v1/home/diagnostics").header("Authorization","Bearer "+two.token)).andExpect(status().isOk).andReturn().response.contentAsString
        assertEquals(1,mapper.readTree(diagnostic).path("devices").asInt())
        assertEquals(1,mapper.readTree(diagnostic).path("libraryRevision").asInt())
        assertFalse(diagnostic.contains(one.token));assertFalse(diagnostic.contains(two.token))
        assertTrue(library.read(principal(one)).library.path("channels").isEmpty)
        assertEquals(1,library.read(principal(two)).library.path("channels").size())
        mvc.perform(post("/api/v1/home/library").header("Authorization","Bearer "+two.token).contentType(MediaType.APPLICATION_JSON).content(mapper.writeValueAsBytes(payload))).andExpect(status().isConflict)
    }
}
