package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.nio.file.Files
import java.nio.file.Path
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

/** The same checked-in FongMi Result fixture used by iOS Swift parser tests. */
@SpringBootTest
@AutoConfigureMockMvc
class MediaProviderGoldenIntegrationTest(@Autowired private val mvc: MockMvc) {
    private val mapper = jacksonObjectMapper()
    private val fixture = Files.readString(Path.of("../../fixtures/p2-fongmi-result.json"))

    private fun request(fields: Map<String, Any> = emptyMap()): String =
        mapper.writeValueAsString(mapOf("content" to fixture) + fields)

    private fun post(path: String, fields: Map<String, Any> = emptyMap()) =
        mvc.perform(
            post("/api/v1/media/$path")
                .contentType(MediaType.APPLICATION_JSON)
                .content(request(fields))
        )

    @Test
    fun sameFixtureSupportsHomeCategorySearchDetailAndPlayback() {
        post("home").andExpect(status().isOk)
            .andExpect(jsonPath("$.total").value(3))
            .andExpect(jsonPath("$.categories.length()").value(2))
            .andExpect(jsonPath("$.items[0].id").value("film-1"))
        post("category", mapOf("categoryId" to "movie"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.total").value(2))
        post("search", mapOf("query" to "FIXTURE"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.total").value(2))
        post("detail", mapOf("vodId" to "film-1"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.lines.length()").value(2))
            .andExpect(jsonPath("$.lines[1].episodes[0].playable").value(false))
        post("play", mapOf("vodId" to "film-1", "lineIndex" to 0, "episodeIndex" to 1))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.url").value("https://example.org/movie2.m3u8"))
        post("play", mapOf("vodId" to "film-1", "lineIndex" to 1, "episodeIndex" to 0))
            .andExpect(status().isUnprocessableEntity)
        post("play", mapOf("vodId" to "unsafe", "lineIndex" to 0, "episodeIndex" to 0))
            .andExpect(status().isUnprocessableEntity)
    }
}
