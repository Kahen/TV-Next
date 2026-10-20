package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

@SpringBootTest
@AutoConfigureMockMvc
class EpgControllerTest(@Autowired private val mvc: MockMvc) {
    private val mapper = jacksonObjectMapper()

    @Test
    fun readsGuideFromExplicitXmlAndM3uChannelIds() {
        val payload = EpgGuideRequest(
            xml = """<tv><channel id="c"><display-name>Fixture TV</display-name></channel>
                <programme channel="c" start="20261020120000 +0000" stop="20261020130000 +0000">
                  <title>Current programme</title></programme></tv>""",
            channels = listOf(EpgChannelRequest(id="c", name="Fixture TV")),
            at = "2026-10-20T12:30:00Z",
            hours = 12
        )
        mvc.perform(post("/api/v1/epg/guide")
            .contentType(MediaType.APPLICATION_JSON)
            .content(mapper.writeValueAsString(payload)))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.matchedChannels").value(1))
            .andExpect(jsonPath("$.channels[0].matchType").value("id"))
            .andExpect(jsonPath("$.channels[0].current.title").value("Current programme"))
    }

    @Test
    fun doctypeRejectedAtHttpBoundary() {
        val payload = EpgGuideRequest(
            xml = """<!DOCTYPE tv [ <!ENTITY x SYSTEM "https://example.org/secret"> ]><tv/>""",
            channels = listOf(EpgChannelRequest(name="Fixture"))
        )
        mvc.perform(post("/api/v1/epg/guide")
            .contentType(MediaType.APPLICATION_JSON)
            .content(mapper.writeValueAsString(payload)))
            .andExpect(status().isBadRequest)
            .andExpect(jsonPath("$.error").exists())
    }
}
