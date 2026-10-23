package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import java.net.URI
import java.net.URLEncoder
import java.util.Base64
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class SiteRequest(val content: String = "", val url: String = "", val siteKey: String = "", val categoryId: String? = null,
    val query: String? = null, val vodId: String? = null, val page: Int = 1, val lineIndex: Int = 0,
    val episodeIndex: Int = 0, val action: String? = null, val filters: Map<String, String> = emptyMap(), val quick: Boolean = false)
data class ProviderPage(val categories: List<MediaCategory>, val items: List<MediaItem>, val total: Int, val page: Int,
    val pageSize: Int, val hasMore: Boolean, val provider: String, val filters: JsonNode)

/** Original SiteApi type 0/1/2/4 request conventions, not a new subscription schema. */
@Service
class SubscribedProvider(private val subscriptions: Subscriptions, private val mapper: ObjectMapper,
    private val parser: StaticFongMiProvider, private val transport: ProviderTransport, private val xml: XmlVodAdapter) {
    fun page(op: String, r: SiteRequest): ProviderPage {
        val site = site(r)
        val root = fetch(site, op, r)
        val data = parser.read(root.toString(), site.path("type").asInt() == 4, true)
        val total = root.path("total").asText().toIntOrNull()?.coerceIn(0, 10_000_000) ?: data.entries.size
        val pages = root.path("pagecount").asText().toIntOrNull()?.coerceAtLeast(1) ?: 1
        val allowed = site.path("categories").map { it.asText() }
        val categories = if (allowed.isEmpty()) data.categories else data.categories.filter { it.name in allowed }.ifEmpty { data.categories }
        return ProviderPage(categories, data.entries.take(100).map { it.item }, total, r.page,
            root.path("limit").asText().toIntOrNull()?.coerceIn(1, 100) ?: 40, r.page < pages,
            r.siteKey, root.path("filters"))
    }
    fun detail(r: SiteRequest): MediaDetail {
        val site = site(r)
        val data = parser.read(fetch(site, "detail", r).toString(), site.path("type").asInt() == 4, true)
        return parser.detail(data, MediaQuery(vodId = r.vodId)).copy(provider = r.siteKey)
    }
    fun play(r: SiteRequest): MediaPlayback {
        val site = site(r)
        val type = site.path("type").asInt()
        val data = parser.read(fetch(site, "detail", r).toString(), site.path("type").asInt() == 4, true)
        val entry = data.entries.firstOrNull { it.item.id == r.vodId } ?: reject("Unknown video", HttpStatus.NOT_FOUND)
        val line = entry.lines.getOrNull(r.lineIndex) ?: reject("Invalid lineIndex")
        val episode = line.episodes.getOrNull(r.episodeIndex) ?: reject("Invalid episodeIndex")
        val target = entry.urls.getOrNull(r.lineIndex)?.getOrNull(r.episodeIndex) ?: reject("Unsupported episode", HttpStatus.UNPROCESSABLE_ENTITY)
        val headers = header(site.path("header"))
        if (type != 4) {
            if (site.path("playUrl").asText("").isNotBlank()) reject("This site requires an external parser", HttpStatus.UNPROCESSABLE_ENTITY)
            Subscriptions.httpUri(target)
            return MediaPlayback(target, episode.name, line.name, r.siteKey, headers)
        }
        val root = fetch(site, "play", r, mapOf("play" to target, "flag" to line.name))
        if (root.path("parse").asInt(0) != 0 || root.path("jx").asInt(0) == 1 || root.path("playUrl").asText("").isNotBlank())
            reject("Playback requires an unsupported parser or WebView", HttpStatus.UNPROCESSABLE_ENTITY)
        val resultUrl = root.path("url").let { node ->
            when {
                node.isTextual -> node.asText()
                node.isArray -> node.get(1)?.asText().orEmpty() // UrlAdapter: name,url,name,url
                node.isObject -> node.path("values").get(node.path("position").asInt(0))?.path("v")?.asText().orEmpty()
                else -> ""
            }
        }
        Subscriptions.httpUri(resultUrl)
        val resultHeaders = header(root.path("header")).ifEmpty { headers }
        return MediaPlayback(resultUrl, episode.name, line.name, r.siteKey, resultHeaders,
            resources(root.path("subs")), resources(root.path("danmaku")))
    }
    fun action(r: SiteRequest): JsonNode {
        val site = site(r)
        if (site.path("type").asInt() != 4) reject("Only HTTP Spider actions are supported",HttpStatus.UNPROCESSABLE_ENTITY)
        val address = r.action?.takeIf { it.isNotBlank() } ?: reject("action required")
        return try { mapper.readTree(transport.get(Subscriptions.httpUri(address))) }
            catch (e: ResponseStatusException) { throw e } catch (_: Exception) { reject("Invalid action response",HttpStatus.BAD_GATEWAY) }
    }
    internal fun params(type: Int, op: String, r: SiteRequest, ext: String): Map<String, String> {
        val p = linkedMapOf<String, String>()
        when (op) {
            "home" -> if (type == 4) p["filter"] = "true"
            "category" -> {
                p["ac"] = if (type == 0) "videolist" else "detail"
                p["t"] = r.categoryId?.takeIf { it.isNotBlank() } ?: reject("categoryId required")
                p["pg"] = r.page.toString()
                if (type == 1 && r.filters.isNotEmpty()) p["f"] = mapper.writeValueAsString(r.filters)
                if (type == 4) p["ext"] = Base64.getUrlEncoder().encodeToString(mapper.writeValueAsBytes(r.filters))
            }
            "detail" -> { p["ac"] = if (type == 0) "videolist" else "detail"; p["ids"] = r.vodId?.takeIf { it.isNotBlank() } ?: reject("vodId required") }
            "search" -> {
                p["wd"] = r.query?.trim()?.takeIf { it.isNotEmpty() } ?: reject("query required")
                p["quick"] = r.quick.toString(); p["extend"] = ""
                if (r.page != 1) p["pg"] = r.page.toString()
            }
        }
        if (ext.isNotBlank() && (op != "home" || type == 4)) p["extend"] = ext
        return p
    }
    private fun site(r: SiteRequest): JsonNode {
        if (r.content.isBlank() || r.page !in 1..1000 || (r.query?.length ?: 0) > 120 || (r.vodId?.length ?: 0) > 16384 ||
            (r.categoryId?.length ?: 0) > 4096 || r.filters.size > 30 || r.filters.any { it.key.length > 100 || it.value.length > 1000 }) reject("Invalid site request")
        val site = subscriptions.site(r.content, r.url, r.siteKey)
        if (site.path("type").asInt(0) !in setOf(0, 1, 2, 4)) reject("This site requires a server Spider adapter", HttpStatus.UNPROCESSABLE_ENTITY)
        return site
    }
    private fun fetch(site: JsonNode, op: String, r: SiteRequest, extra: Map<String, String> = emptyMap()): JsonNode {
        val type = site.path("type").asInt(0)
        var ext = site.path("ext").let { if (it.isContainerNode) it.toString() else it.asText("") }
        if (type == 4 && ext.startsWith("http")) ext = transport.get(Subscriptions.httpUri(ext))
        val p = params(type, op, r, ext) + extra
        val endpoint = Subscriptions.httpUri(site.path("api").asText())
        val body = p.entries.joinToString("&") { URLEncoder.encode(it.key, Charsets.UTF_8) + "=" + URLEncoder.encode(it.value, Charsets.UTF_8) }
        val post = ext.length > 1000 && (op != "home" || type == 4)
        val url = if (post || body.isEmpty()) endpoint else URI(endpoint.toString() + (if (endpoint.rawQuery == null) "?" else "&") + body)
        val text = transport.get(url, header(site.path("header")), if (post) body else null)
        val root = try { if (type == 0) xml.parse(text) else mapper.readTree(text) }
            catch (e: ResponseStatusException) { throw e } catch (_: Exception) { reject("Invalid provider response", HttpStatus.BAD_GATEWAY) }
        if (root == null || !root.isObject) reject("Invalid provider object", HttpStatus.BAD_GATEWAY)
        return root
    }
    private fun header(raw: JsonNode): Map<String, String> {
        val node = if (raw.isTextual) runCatching { mapper.readTree(raw.asText()) }.getOrNull() else raw
        val map = if (node?.isObject == true) node.fields().asSequence().associate { it.key to it.value.asText() } else emptyMap()
        ProviderTransport.validateHeaders(map)
        return map
    }
    private fun resources(raw: JsonNode): List<PlaybackResource> {
        val node = if (raw.isTextual && raw.asText().trim().startsWith("[")) runCatching { mapper.readTree(raw.asText()) }.getOrNull() ?: raw else raw
        if (node.isTextual) return runCatching { Subscriptions.httpUri(node.asText()); listOf(PlaybackResource("Default", node.asText())) }.getOrDefault(emptyList())
        return node.takeIf { it.isArray }?.take(30)?.mapNotNull {
            val url = it.path("url").asText("")
            if (runCatching { Subscriptions.httpUri(url) }.isFailure) null else PlaybackResource(it.path("name").asText("Default").take(200), url, it.path("lang").asText("").ifBlank { null })
        }.orEmpty()
    }
    private fun reject(message: String, status: HttpStatus = HttpStatus.BAD_REQUEST): Nothing = throw ResponseStatusException(status, message)
}
@RestController
@RequestMapping("/api/v1/subscriptions")
class SubscribedProviderController(private val service: SubscribedProvider) {
    @PostMapping("/action") fun action(@RequestBody r: SiteRequest) = service.action(r)
    @PostMapping("/home") fun home(@RequestBody r: SiteRequest) = service.page("home", r)
    @PostMapping("/category") fun category(@RequestBody r: SiteRequest) = service.page("category", r)
    @PostMapping("/search") fun search(@RequestBody r: SiteRequest) = service.page("search", r)
    @PostMapping("/detail") fun detail(@RequestBody r: SiteRequest) = service.detail(r)
    @PostMapping("/play") fun play(@RequestBody r: SiteRequest) = service.play(r)
}
