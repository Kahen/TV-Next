package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith
import org.springframework.http.HttpStatus
import org.springframework.web.server.ResponseStatusException

class MediaProviderTest {
    private val provider = StaticFongMiProvider(jacksonObjectMapper())
    private val fixture = """
        {
          "class": [{"type_id":"movie","type_name":"Movies"},{"type_id":"series","type_name":"Series"}],
          "list": [
            {"vod_id":"m1","vod_name":"Example Movie","type_id":"movie","vod_year":"2026",
             "vod_remarks":"HD","vod_content":"Sample text",
             "vod_play_from":"Direct${'$'}${'$'}${'$'}Plugin",
             "vod_play_url":"Part 1${'$'}https://example.org/m1.mp4#Part 2${'$'}https://example.org/m2.m3u8${'$'}${'$'}${'$'}Captcha${'$'}script://requires-plugin"},
            {"vod_id":"s1","vod_name":"Example Series","type_id":"series","vod_play_from":"Line","vod_play_url":"E1${'$'}https://example.org/s1.mp4"},
            {"vod_id":"x3","vod_name":"No Url","type_id":"movie","vod_pic":"javascript:alert(1)"}
          ]
        }
    """.trimIndent()
    private val media get() = provider.read(fixture)

    @Test fun homeReturnsCategoriesAndItems() {
        val page = provider.home(media, MediaQuery())
        assertEquals(2, page.categories.size)
        assertEquals(3, page.total)
        assertEquals("static-fongmi-result", page.provider)
    }

    @Test fun categoryAndSearchSupportPagination() {
        val page = provider.category(media, MediaQuery(categoryId="movie", pageSize=1))
        assertEquals(2, page.total)
        assertEquals(1, page.items.size)
        assertTrue(page.hasMore)
        val page2 = provider.category(media, MediaQuery(categoryId="movie", page=2, pageSize=1))
        assertFalse(page2.hasMore)
        val search = provider.search(media, MediaQuery(query="EXAMPLE"))
        assertEquals(2, search.total)
    }

    @Test fun detailAndEpisodeSelectionPreserveLines() {
        val detail = provider.detail(media, MediaQuery(vodId="m1"))
        assertEquals("Example Movie", detail.item.name)
        assertEquals(2, detail.lines.size)
        assertEquals(listOf("Part 1","Part 2"), detail.lines[0].episodes.map { it.name })
        assertTrue(detail.lines[0].episodes[0].playable)
        assertFalse(detail.lines[1].episodes[0].playable)
        val playback = provider.play(media, MediaQuery(vodId="m1",lineIndex=0,episodeIndex=1))
        assertEquals("https://example.org/m2.m3u8",playback.url)
        val fail = assertFailsWith<ResponseStatusException> {
            provider.play(media, MediaQuery(vodId="m1",lineIndex=1,episodeIndex=0))
        }
        assertEquals(HttpStatus.UNPROCESSABLE_ENTITY, fail.statusCode)
    }

    @Test fun invalidJsonAndUrlsAreNeverExecuted() {
        assertEquals(null, provider.detail(media, MediaQuery(vodId="x3")).item.poster)
        listOf("{}", "[]", """{"list":{}}""", """{"list":[{"vod_id":"1","vod_name":"x"}],"class":null}""",
            "x".repeat(1_048_577)).forEach { input ->
            assertFailsWith<ResponseStatusException> { provider.read(input) }
        }
        assertFailsWith<ResponseStatusException> { provider.search(media, MediaQuery(query="")) }
        assertFailsWith<ResponseStatusException> { provider.category(media, MediaQuery(categoryId="movie",pageSize=1000)) }
        assertEquals(HttpStatus.NOT_FOUND,
            assertFailsWith<ResponseStatusException> { provider.detail(media,MediaQuery(vodId="missing")) }.statusCode)
    }

    @Test fun duplicatesAndUnsafeUrlsAreIgnored() {
        val data = provider.read("""{"list":[
          {"vod_id":"1","vod_name":"First","vod_play_from":"Line","vod_play_url":"A${'$'}https://user:pass@example.org/movie"},
          {"vod_id":"1","vod_name":"Duplicate"},
          {"vod_id":"2","vod_name":"Second","vod_play_from":"Line","vod_play_url":"A${'$'}javascript:alert(1)"}
        ]}""")
        assertEquals(2, data.entries.size)
        assertFalse(data.entries[0].lines.single().episodes.single().playable)
        assertFalse(data.entries[1].lines.single().episodes.single().playable)
    }
}
