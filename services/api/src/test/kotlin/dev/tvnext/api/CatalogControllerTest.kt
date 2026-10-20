package dev.tvnext.api

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
class CatalogControllerTest(@Autowired private val mvc: MockMvc) {
    @Test
    fun exposesStaticNormalizedCatalogWithoutRuntimeExecution() {
        val config = """{"sites":[{"key":"test","name":"Sample","type":3}],"lives":[{"name":"Demo","groups":[{"name":"News","channel":[{"name":"Channel","urls":["https://example.org/live.m3u8"]}]}]}]}"""
        val request = """{"content":""" + com.fasterxml.jackson.module.kotlin.jacksonObjectMapper()
            .writeValueAsString(config) + "}"
        mvc.perform(post("/api/v1/catalog/preview")
            .contentType(MediaType.APPLICATION_JSON)
            .content(request))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.sites[0].key").value("test"))
            .andExpect(jsonPath("$.sites[0].mode").value("preview-only"))
            .andExpect(jsonPath("$.liveSources[0].groups[0].channels[0].name").value("Channel"))
            .andExpect(jsonPath("$.directPlayableChannelCount").value(1))
    }
}
