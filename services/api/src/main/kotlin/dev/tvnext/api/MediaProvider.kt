package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URI
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException

/**
 * Version 1 of the media provider contract, independent of Android classes.
 * Provider implementations must NOT use client input as permission for HTTP fetches.
 */
data class MediaQuery(
    val content: String = "",
    val categoryId: String? = null,
    val query: String? = null,
    val vodId: String? = null,
    val page: Int = 1,
    val pageSize: Int = 40,
    val lineIndex: Int = 0,
    val episodeIndex: Int = 0
)
data class MediaCategory(val id: String, val name: String)
data class MediaItem(
    val id: String,
    val name: String,
    val categoryId: String?,
    val categoryName: String?,
    val poster: String?,
    val remarks: String?,
    val year: String?,
    val folder: Boolean = false,
    val action: String? = null
)
data class MediaEpisode(val name: String, val playable: Boolean)
data class MediaLine(val name: String, val episodes: List<MediaEpisode>)
data class MediaPage(
    val categories: List<MediaCategory>,
    val items: List<MediaItem>,
    val total: Int,
    val page: Int,
    val pageSize: Int,
    val hasMore: Boolean,
    val provider: String = "static-fongmi-result"
)
data class MediaDetail(
    val item: MediaItem,
    val description: String?,
    val director: String?,
    val actors: String?,
    val lines: List<MediaLine>,
    val provider: String = "static-fongmi-result"
)
data class MediaPlayback(
    val url: String,
    val name: String,
    val lineName: String,
    val provider: String = "static-fongmi-result",
    val headers: Map<String, String> = emptyMap(),
    val subtitles: List<PlaybackResource> = emptyList(),
    val danmaku: List<PlaybackResource> = emptyList()
)
data class PlaybackResource(val name: String, val url: String, val lang: String? = null)
data class MediaContent(val categories: List<MediaCategory>, val entries: List<MediaEntry>)
data class MediaEntry(
    val item: MediaItem,
    val description: String?,
    val director: String?,
    val actors: String?,
    val lines: List<MediaLine>,
    val urls: List<List<String?>>
)

interface MediaProvider {
    fun home(data: MediaContent, request: MediaQuery): MediaPage
    fun category(data: MediaContent, request: MediaQuery): MediaPage
    fun search(data: MediaContent, request: MediaQuery): MediaPage
    fun detail(data: MediaContent, request: MediaQuery): MediaDetail
    fun play(data: MediaContent, request: MediaQuery): MediaPlayback
}

/**
 * Strict and bounded adapter for user-pasted FongMi "Result" JSON with
 * class/list and vod_* fields. Never runs Spider or downloads a resource.
 */
@Service
class StaticFongMiProvider(private val mapper: ObjectMapper) : MediaProvider {
    companion object {
        private const val MAX_CONTENT = 1_048_576
        private const val MAX_LIST = 2_000
        private const val MAX_LINES = 30
        private const val MAX_EPISODES = 400
        private const val MAX_CATEGORIES = 200
        private const val MAX_TEXT = 2_000
    }

    fun read(content: String, resolveOpaque: Boolean = false): MediaContent {
        if (content.isBlank() || content.length > MAX_CONTENT || content.toByteArray(Charsets.UTF_8).size > MAX_CONTENT) bad("Media JSON must be 1..1048576 chars")
        val root = try { mapper.readTree(content) } catch (_: Exception) { bad("Invalid media JSON") }
        if (root == null || !root.isObject) bad("Expected JSON object")
        val types = root.path("class")
        val videos = root.path("list")
        if ((!types.isMissingNode && !types.isArray) || (!videos.isMissingNode && !videos.isArray)) {
            bad("class and list must be arrays")
        }
        if (types.isMissingNode && videos.isMissingNode) bad("Expected FongMi class or list")
        if (types.size() > MAX_CATEGORIES || videos.size() > MAX_LIST) bad("Catalog exceeds limits")
        val categoryIds = mutableSetOf<String>()
        val categories = types.filter { it.isObject }.mapNotNull { node ->
            val id = string(node.path("type_id"), 100)
            if (id.isBlank() || !categoryIds.add(id)) null
            else MediaCategory(id, string(node.path("type_name"), 150).ifBlank { id })
        }
        val ids = mutableSetOf<String>()
        val entries = videos.filter { it.isObject }.mapNotNull { node ->
            val id = string(node.path("vod_id"), if (resolveOpaque) 16384 else 200)
            val name = string(node.path("vod_name"), 200)
            if (id.isBlank() || name.isBlank() || !ids.add(id)) return@mapNotNull null
            val item = MediaItem(
                id, name,
                string(node.path("type_id"), 100).ifBlank { null },
                string(node.path("type_name"), 150).ifBlank { null },
                string(node.path("vod_pic"), 2048).takeIf { validUrl(it) },
                string(node.path("vod_remarks"), 150).ifBlank { null },
                string(node.path("vod_year"), 30).ifBlank { null },
                node.path("vod_tag").asText() == "folder" || node.path("cate").isObject,
                string(node.path("action"), 8192).ifBlank { null }
            )
            val lineNames = string(node.path("vod_play_from"), MAX_TEXT)
                .split("$$$")
                .take(MAX_LINES)

            val episodeGroups = string(node.path("vod_play_url"), MAX_CONTENT)
                .split("$$$")
                .take(MAX_LINES)
            val lines = mutableListOf<MediaLine>()
            val urls = mutableListOf<List<String?>>()
            for (index in lineNames.indices) {
                val rawEpisodes = episodeGroups.getOrNull(index).orEmpty()
                val parsed = rawEpisodes.split("#").take(MAX_EPISODES).mapNotNull { raw ->
                    if (raw.isBlank()) return@mapNotNull null
                    val split = raw.indexOf('$')
                    val label = if (split >= 0) raw.substring(0, split).trim().take(150).ifBlank { "Episode" } else "Episode"
                    val target = if (split >= 0) raw.substring(split + 1) else raw
                    val playable = target.takeIf { validUrl(it) || resolveOpaque && it.isNotBlank() && it.length <= 16384 && !it.any { c -> Character.isISOControl(c) } }
                    Pair(MediaEpisode(label, playable != null), playable)
                }
                if (parsed.isNotEmpty()) {
                    lines += MediaLine(lineNames[index].take(120).ifBlank { "Line ${index + 1}" }, parsed.map { it.first })
                    urls += parsed.map { it.second }
                }
            }
            MediaEntry(
                item,
                string(node.path("vod_content"), MAX_TEXT).ifBlank { null },
                string(node.path("vod_director"), 300).ifBlank { null },
                string(node.path("vod_actor"), 300).ifBlank { null },
                lines, urls
            )
        }
        return MediaContent(categories, entries)
    }

    override fun home(data: MediaContent, request: MediaQuery): MediaPage = page(data, request, data.entries)
    override fun category(data: MediaContent, request: MediaQuery): MediaPage {
        val id = request.categoryId?.takeIf { it.isNotBlank() } ?: bad("categoryId required")
        if (id.length > 100) bad("categoryId too long")
        return page(data, request, data.entries.filter {
            it.item.categoryId == id || (it.item.categoryId == null && it.item.categoryName == id)
        })
    }

    override fun search(data: MediaContent, request: MediaQuery): MediaPage {
        val text = request.query?.trim()?.takeIf { it.isNotEmpty() } ?: bad("query required")
        if (text.length > 120) bad("query too long")
        return page(data, request, data.entries.filter {
            it.item.name.contains(text, ignoreCase = true)
        })
    }

    override fun detail(data: MediaContent, request: MediaQuery): MediaDetail {
        val video = entry(data, request.vodId)
        return MediaDetail(video.item, video.description, video.director, video.actors, video.lines)
    }

    override fun play(data: MediaContent, request: MediaQuery): MediaPlayback {
        val video = entry(data, request.vodId)
        if (request.lineIndex !in video.urls.indices) bad("Invalid lineIndex")
        val urls = video.urls[request.lineIndex]
        if (request.episodeIndex !in urls.indices) bad("Invalid episodeIndex")
        val url = urls[request.episodeIndex]
            ?: throw ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Episode requires an unsupported parser")
        return MediaPlayback(url, video.lines[request.lineIndex].episodes[request.episodeIndex].name,
            video.lines[request.lineIndex].name)
    }

    private fun entry(data: MediaContent, id: String?): MediaEntry {
        if (id.isNullOrBlank() || id.length > 16384) bad("vodId required")
        return data.entries.firstOrNull { it.item.id == id }
            ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown video ID")
    }

    private fun page(data: MediaContent, query: MediaQuery, entries: List<MediaEntry>): MediaPage {
        if (query.page !in 1..1000 || query.pageSize !in 1..100) bad("Invalid pagination")
        val offset = (query.page - 1) * query.pageSize
        val items = entries.drop(offset).take(query.pageSize).map { it.item }
        return MediaPage(data.categories, items, entries.size, query.page, query.pageSize,
            offset + items.size < entries.size)
    }

    private fun string(node: JsonNode, max: Int): String =
        if (node.isTextual || node.isIntegralNumber) node.asText().take(max).trim() else ""

    private fun validUrl(value: String): Boolean {
        if (value.isBlank() || value.length > 2048 || value.any { Character.isISOControl(it) }) return false
        val uri = runCatching { URI(value) }.getOrNull() ?: return false
        return uri.scheme?.lowercase() in setOf("http", "https") &&
            !uri.host.isNullOrBlank() && uri.rawUserInfo == null
    }

    private fun bad(message: String): Nothing = throw ResponseStatusException(HttpStatus.BAD_REQUEST, message)
}

@RestController
@RequestMapping("/api/v1/media")
class MediaProviderController(private val provider: StaticFongMiProvider) {
    @PostMapping("/home")
    fun home(@RequestBody request: MediaQuery): MediaPage = provider.home(provider.read(request.content), request)
    @PostMapping("/category")
    fun category(@RequestBody request: MediaQuery): MediaPage = provider.category(provider.read(request.content), request)
    @PostMapping("/search")
    fun search(@RequestBody request: MediaQuery): MediaPage = provider.search(provider.read(request.content), request)
    @PostMapping("/detail")
    fun detail(@RequestBody request: MediaQuery): MediaDetail = provider.detail(provider.read(request.content), request)
    @PostMapping("/play")
    fun play(@RequestBody request: MediaQuery): MediaPlayback = provider.play(provider.read(request.content), request)
}
