package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.springframework.web.server.ResponseStatusException

class ConfigCatalogTest {
    private val catalog = ConfigCatalog(jacksonObjectMapper())

    @Test
    fun normalizesFongMiSitesAndLiveGroupsWithoutExecutingPlugins() {
        val config = """
            {
              "spider": "https://example.org/never-fetched.jar",
              "sites": [
                {"key":"demo","name":"Example","api":"csp_Example","type":3,"searchable":0,"hide":1,"categories":["Drama","Movies"]},
                {"key":"demo","name":"Duplicated"}
              ],
              "lives":[{"name":"IPTV","groups":[{"name":"News","channel":[
                {"name":"Public","urls":["https://example.org/channel.m3u8"]},
                {"name":"Spider","urls":["script://secret"]},
                {"name":"Credentials","urls":["https://user:secret@example.org/live"]}
              ]}]}]
            }
        """.trimIndent()
        val result = catalog.preview(config)
        assertEquals(1, result.sites.size)
        assertEquals("demo", result.sites.single().key)
        assertFalse(result.sites.single().searchable)
        assertTrue(result.sites.single().hidden)
        assertEquals(listOf("Drama", "Movies"), result.sites.single().categories)
        assertEquals("preview-only", result.sites.single().mode)
        assertEquals(1, result.directPlayableChannelCount)
        val channels = result.liveSources.single().groups.single().channels
        assertEquals("https://example.org/channel.m3u8", channels[0].directUrl)
        assertEquals(null, channels[1].directUrl)
        assertEquals(null, channels[2].directUrl)
    }

    @Test fun originalSearchableStateTwoMeansDisabled() {
        assertFalse(catalog.preview("""{"sites":[{"key":"disabled","searchable":2}]}""").sites.single().searchable)
        assertTrue(catalog.preview("""{"sites":[{"key":"default"}]}""").sites.single().searchable)
    }

    @Test
    fun rejectsInvalidConfigsAndTooLargeText() {
        assertTrue(catalog.preview("{}").sites.isEmpty())
        for (input in listOf("[]", "{", """{"sites":{}}""", """{"lives":"bad"}""")) {
            assertFailsWith<ResponseStatusException> { catalog.preview(input) }
        }
        assertFailsWith<ResponseStatusException> { catalog.preview("a".repeat(1_048_577)) }
    }
}
