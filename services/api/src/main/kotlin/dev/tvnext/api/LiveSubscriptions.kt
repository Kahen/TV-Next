package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class LiveImportRequest(val content: String = "", val url: String = "", val liveIndex: Int = 0)
data class LiveImportResponse(val channels: List<Channel>, val total: Int, val warnings: List<String>)

/** LiveParser TXT/M3U/group JSON and LiveConfig external references, restricted to HTTP(S) media. */
@Service
class LiveSubscriptions(private val mapper: ObjectMapper, private val subscriptions: Subscriptions,
    private val transport: ProviderTransport, private val m3u: PlaylistParser) {
    fun load(r: LiveImportRequest): LiveImportResponse {
        if (r.liveIndex !in 0..49) bad("Invalid liveIndex")
        var content = r.content.ifBlank { transport.get(Subscriptions.httpUri(r.url)) }
        var base = r.url
        var headers = emptyMap<String,String>()
        val warnings = mutableListOf<String>()
        if (content.trimStart().startsWith("{") || content.contains("**") || content.trimStart().startsWith("2423")) {
            val doc = subscriptions.load(SubscriptionRequest(content,base))
            val root = mapper.readTree(doc.content)
            val live = root.path("lives").get(r.liveIndex) ?: bad("Unknown live source")
            if (live.path("api").asText("").isNotBlank()) bad("This live source requires a Spider runtime")
            val rawHeaders = live.path("header")
            val node = if (rawHeaders.isTextual) runCatching { mapper.readTree(rawHeaders.asText()) }.getOrNull() else rawHeaders
            headers = (node?.takeIf { it.isObject }?.fields()?.asSequence()?.associate { it.key to it.value.asText() }).orEmpty().toMutableMap().apply {
                mapOf("ua" to "User-Agent","referer" to "Referer","origin" to "Origin").forEach { (field,name) ->
                    live.path(field).asText("").takeIf { it.isNotBlank() }?.let { put(name,it) }
                }
            }
            ProviderTransport.validateHeaders(headers)
            content = if (live.path("groups").isArray && !live.path("groups").isEmpty) live.path("groups").toString() else {
                base = live.path("url").asText("")
                transport.get(Subscriptions.httpUri(base),headers)
            }
        }
        if (content.toByteArray(Charsets.UTF_8).size > 1_048_576) bad("Live playlist exceeds 1 MiB")
        if (headers.isNotEmpty()) warnings += "Live source request headers are retained; native header-dependent playback requires a media adapter."
        val channels = when {
            content.trimStart().startsWith("[") -> groups(content,warnings)
            Regex("(?im)^#EXTM3U").containsMatchIn(content) -> {
                if (Regex("(?im)^#EXTVLCOPT|^#EXTHTTP|\\|(?:User-Agent|Referer|Cookie)").containsMatchIn(content))
                    warnings += "This M3U declares media request headers; unsupported options must be checked before native playback."
                m3u.parse(content).channels
            }
            else -> txt(content,warnings)
        }
        return LiveImportResponse(channels.map { it.copy(headers = headers + it.headers) },channels.size,warnings.distinct())
    }
    private fun groups(content: String, warnings: MutableList<String>): List<Channel> {
        val root = try { mapper.readTree(content) } catch (_: Exception) { bad("Invalid live group JSON") }
        if (!root.isArray || root.size() > 100) bad("Invalid live groups")
        val result = mutableListOf<Channel>()
        root.forEach { group ->
            group.path("channel").take(1000).forEach { channel ->
                val urls = channel.path("urls").take(20).map { it.asText() }
                val accepted = urls.filter { valid(it) }
                if (accepted.size < urls.size) warnings += "Some live protocols need a server adapter."
                val channelHeaders = channel.path("header").takeIf { it.isObject }?.fields()?.asSequence()?.associate { it.key to it.value.asText() }.orEmpty()
                ProviderTransport.validateHeaders(channelHeaders)
                accepted.forEach { url -> add(result,Channel(channel.path("name").asText("Unnamed").take(200),url,group.path("name").asText("Uncategorized").take(100),headers=channelHeaders)) }
            }
        }
        return result
    }
    private fun txt(content: String, warnings: MutableList<String>): List<Channel> {
        val lines = content.replace("\r\n","\n").replace('\r','\n').split('\n')
        if (lines.size > 20_000) bad("Too many live lines")
        var group = "Uncategorized"
        val result = mutableListOf<Channel>()
        for (raw in lines) {
            val line = raw.trim()
            val split = line.indexOf(',')
            if (line.contains("#genre#")) { group = line.substringBefore(',').trim().take(100); continue }
            if (split < 1) continue
            val name = line.substring(0,split).trim().take(200)
            line.substring(split+1).split('#').take(20).forEach { source ->
                if (source.contains('|')) warnings += "Inline live headers require a media adapter."
                val url = source.substringBefore('|').trim()
                if (valid(url)) add(result,Channel(name,url,group,headers=LiveHeaders.inline(source.substringAfter('|',""))))
                else if (url.contains("://")) warnings += "Some live protocols need a server adapter."
            }
        }
        return result
    }
    private fun add(result: MutableList<Channel>, channel: Channel) {
        if (result.size >= 5000) bad("Too many live channels")
        result.add(channel)
    }
    private fun valid(url: String) = url.length <= 2048 && runCatching { Subscriptions.httpUri(url) }.isSuccess
    private fun bad(message: String): Nothing = throw ResponseStatusException(HttpStatus.BAD_REQUEST,message)
}
@RestController
@RequestMapping("/api/v1/subscriptions")
class LiveSubscriptionController(private val lives: LiveSubscriptions) {
    @PostMapping("/live") fun live(@RequestBody r: LiveImportRequest) = lives.load(r)
}

internal object LiveHeaders {
    fun inline(value: String): Map<String,String> {
        val headers = value.split('&').filter { it.contains('=') }.associate { part ->
            part.substringBefore('=').trim().trim('"') to part.substringAfter('=').trim().trim('"')
        }
        ProviderTransport.validateHeaders(headers)
        return headers
    }
}
