package dev.tvnext.api

import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URI
import java.util.UUID
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
class LiveReplayIntegrationTest @Autowired constructor(private val mvc: MockMvc,private val mapper: ObjectMapper,
    private val accounts: HomeAccounts,private val fixture: ReplayTransport) {
    class ReplayTransport: ProviderTransport() {
        var calls=0
        override fun get(uri: URI,headers: Map<String,String>,form: String?): String {
            calls++
            check(headers.isEmpty())
            return """{"url":"https://example.org/live.m3u8","header":{"Cookie":"provider-secret"}}"""
        }
    }
    @TestConfiguration class Config { @Bean @Primary fun replayTransport()=ReplayTransport() }
    @Test fun authorizationPrecedesIoAndCapabilityCanBeRevokedWithoutReturningProviderSecrets() {
        val now=System.currentTimeMillis()
        val body=mapper.writeValueAsString(LiveReplayRequest(Channel("News","https://example.org/live","Live",
            timeshift=LiveTimeshift("https://example.org/seek?time={time}",now-3_600_000,3_600_000)),0))
        val previousCalls=fixture.calls
        mvc.perform(post("/api/v1/subscriptions/replay").contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isUnauthorized)
        assertEquals(previousCalls,fixture.calls)
        val session=accounts.register(Credentials("replay-"+UUID.randomUUID(),"long-test-password","Replay"))
        val response=mvc.perform(post("/api/v1/subscriptions/replay").header("Authorization","Bearer "+session.token)
            .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isOk).andReturn().response
        val value=mapper.readTree(response.contentAsString)
        assertTrue(value.path("hls").asBoolean());assertEquals(0L,value.path("time").asLong())
        assertFalse(response.contentAsString.contains("example.org"));assertFalse(response.contentAsString.contains("provider-secret"))
        assertEquals("no-store, private",response.getHeader("Cache-Control"))
        val path=value.path("path").asText()
        assertTrue(Regex("/api/v1/home/media/[A-Za-z0-9_-]{43}/0").matches(path))
        accounts.revoke(accounts.principal("Bearer "+session.token),session.device.id)
        mvc.perform(get(path)).andExpect(status().isUnauthorized)
        mvc.perform(post("/api/v1/subscriptions/replay").header("Authorization","Bearer "+session.token)
            .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isUnauthorized)
    }
}
