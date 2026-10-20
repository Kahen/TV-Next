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
class MediaProviderControllerTest(@Autowired private val mvc: MockMvc) {
    private val json = jacksonObjectMapper()
    private val result = """{"class":[{"type_id":"movie","type_name":"Movies"}],"list":[{"vod_id":"1","vod_name":"Fixture","type_id":"movie","vod_play_from":"Direct","vod_play_url":"1$https://example.org/1.mp4"}]}"""

    private fun request(extra: Map<String, Any?> = emptyMap()): String =
        json.writeValueAsString(mapOf("content" to result) + extra)

    @Test fun fullBrowseSearchDetailPlayFlow() {
        mvc.perform(post("/api/v1/media/home").contentType(MediaType.APPLICATION_JSON)
            .content(request())).andExpect(status().isOk)
            .andExpect(jsonPath("$.categories[0].id").value("movie"))
            .andExpect(jsonPath("$.items[0].name").value("Fixture"))
        mvc.perform(post("/api/v1/media/category").contentType(MediaType.APPLICATION_JSON)
            .content(request(mapOf("categoryId" to "movie")))).andExpect(status().isOk)
            .andExpect(jsonPath("$.total").value(1))
        mvc.perform(post("/api/v1/media/search").contentType(MediaType.APPLICATION_JSON)
            .content(request(mapOf("query" to "fix")))).andExpect(status().isOk)
            .andExpect(jsonPath("$.total").value(1))
        mvc.perform(post("/api/v1/media/detail").contentType(MediaType.APPLICATION_JSON)
            .content(request(mapOf("vodId" to "1")))).andExpect(status().isOk)
            .andExpect(jsonPath("$.lines[0].episodes[0].playable").value(true))
        mvc.perform(post("/api/v1/media/play").contentType(MediaType.APPLICATION_JSON)
            .content(request(mapOf("vodId" to "1","lineIndex" to 0,"episodeIndex" to 0))))
            .andExpect(status().isOk).andExpect(jsonPath("$.url").value("https://example.org/1.mp4"))
    }

    @Test fun missingItemIs404() {
        mvc.perform(post("/api/v1/media/detail").contentType(MediaType.APPLICATION_JSON)
            .content(request(mapOf("vodId" to "absent")))).andExpect(status().isNotFound)
    }
}
