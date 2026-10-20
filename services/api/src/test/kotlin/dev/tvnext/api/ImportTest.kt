package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.springframework.web.server.ResponseStatusException

class ImportTest {
    @Test
    fun parsesM3uAndAttributes() {
        val content = """
            #EXTM3U
            #EXTINF:-1 tvg-id="one" group-title="News",Example
            https://example.org/live.m3u8
        """.trimIndent()
        val channel = PlaylistParser().parse(content).channels.single()
        assertEquals("Example", channel.name)
        assertEquals("News", channel.group)
        assertEquals("one", channel.tvgId)
    }

    @Test
    fun filtersUnsupportedAndUnsafeSchemes() {
        val content = "#EXTM3U\n#EXTINF:-1,Javascript\njavascript:alert(1)\n#EXTINF:-1,Embedded secrets\nhttps://user:pass@example.org/x.mp4"
        assertEquals(0, PlaylistParser().parse(content).total)
    }

    @Test
    fun rejectsOversizeContent() {
        assertFailsWith<ResponseStatusException> { PlaylistParser().parse("x".repeat(1_048_577)) }
    }

    @Test
    fun inspectNeverExecutesSpider() {
        val result = ConfigInspector(jacksonObjectMapper()).inspect("""{"spider":"./spider.jar","sites":[{"key":"demo","name":"Example","type":3}],"lives":[{}]}""")
        assertTrue(result.spiderDeclared)
        assertEquals("demo", result.sites.single().key)
        assertEquals(1, result.liveGroupCount)
        assertFalse(ConfigInspector(jacksonObjectMapper()).inspect("{}").spiderDeclared)
    }
}
