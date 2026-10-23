package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URI
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.server.ResponseStatusException

data class CatalogSite(
    val key: String,
    val name: String,
    val type: Int?,
    val searchable: Boolean,
    val hidden: Boolean,
    val categories: List<String>,
    val mode: String = "preview-only"
)
data class CatalogChannel(val name: String, val directUrl: String?, val sourceCount: Int)
data class CatalogGroup(val name: String, val channels: List<CatalogChannel>)
data class CatalogLiveSource(val name: String, val groups: List<CatalogGroup>)
data class CatalogPreviewResponse(
    val sites: List<CatalogSite>,
    val liveSources: List<CatalogLiveSource>,
    val directPlayableChannelCount: Int,
    val warnings: List<String>
)

/** Metadata-only normalization: never fetch URLs, execute Spider or return custom credentials/headers. */
@Service
class ConfigCatalog(private val mapper: ObjectMapper) {
    fun preview(content: String): CatalogPreviewResponse {
        if (content.isBlank() || content.length > 1_048_576 || content.toByteArray(Charsets.UTF_8).size > 1_048_576) reject("Config must be 1..1048576 characters")
        val root = try { mapper.readTree(content) } catch (_: Exception) { reject("Invalid JSON config") }
        if (root == null || !root.isObject) reject("Expected JSON object")
        val siteNodes = root.path("sites")
        val liveNodes = root.path("lives")
        if (!siteNodes.isMissingNode && !siteNodes.isArray) reject("sites must be an array")
        if (!liveNodes.isMissingNode && !liveNodes.isArray) reject("lives must be an array")
        val warnings = mutableListOf<String>()
        if (siteNodes.isArray && siteNodes.size() > 1000) warnings += "Only 1000 sites shown"
        if (liveNodes.isArray && liveNodes.size() > 50) warnings += "Only 50 live sources shown"

        val keys = mutableSetOf<String>()
        val sites = siteNodes.take(1000).mapNotNull { site ->
            if (!site.isObject) return@mapNotNull null
            val key = text(site.path("key"), 200)
            if (key.isBlank() || !keys.add(key)) return@mapNotNull null
            val categories = site.path("categories")
                .takeIf { it.isArray }?.take(50)
                ?.mapNotNull { entry -> text(entry, 100).takeIf { it.isNotBlank() } } ?: emptyList()
            CatalogSite(
                key, text(site.path("name"), 200).ifBlank { key },
                site.path("type").takeIf { it.isInt }?.asInt(),
                site.path("searchable").takeIf { it.isInt }?.asInt() != 0,
                site.path("hide").asInt(0) == 1, categories
            )
        }
        var totalChannels = 0
        val lives = liveNodes.take(50).mapIndexedNotNull { liveIndex, live ->
            if (!live.isObject) return@mapIndexedNotNull null
            val groupNodes = live.path("groups")
            if (!groupNodes.isMissingNode && !groupNodes.isArray) return@mapIndexedNotNull null
            if (groupNodes.isArray && groupNodes.size() > 100) warnings += "Group limit in live source " + (liveIndex + 1)
            val groups = groupNodes.take(100).mapIndexedNotNull { groupIndex, group ->
                if (!group.isObject) return@mapIndexedNotNull null
                val entries = group.path("channel")
                if (!entries.isMissingNode && !entries.isArray) return@mapIndexedNotNull null
                val channels = mutableListOf<CatalogChannel>()
                entries.take(1000).forEach { item ->
                    if (totalChannels >= 5000 || !item.isObject) return@forEach
                    val name = text(item.path("name"), 200)
                    if (name.isBlank()) return@forEach
                    val urls = item.path("urls")
                    val direct = urls.takeIf { it.isArray }?.take(10)?.firstNotNullOfOrNull {
                        it.takeIf { node -> node.isTextual }?.asText()?.takeIf { value -> safeStreamUrl(value) }
                    }
                    channels += CatalogChannel(name, direct, if (urls.isArray) urls.size() else 0)
                    totalChannels++
                }
                CatalogGroup(text(group.path("name"), 100).ifBlank { "Group " + (groupIndex + 1) }, channels)
            }
            CatalogLiveSource(text(live.path("name"), 100).ifBlank { "Live " + (liveIndex + 1) }, groups)
        }
        if (totalChannels >= 5000) warnings += "Channel limit (5000) reached"
        return CatalogPreviewResponse(
            sites, lives,
            lives.sumOf { live -> live.groups.sumOf { group -> group.channels.count { it.directUrl != null } } },
            warnings.distinct().take(30)
        )
    }

    private fun safeStreamUrl(value: String): Boolean {
        if (value.isBlank() || value.length > 2048 || value.any { Character.isISOControl(it) }) return false
        val uri = runCatching { URI(value) }.getOrNull() ?: return false
        return uri.scheme?.lowercase() in setOf("http", "https") &&
            !uri.host.isNullOrBlank() && uri.rawUserInfo == null
    }

    private fun text(node: JsonNode, limit: Int): String =
        if (node.isTextual) node.asText().take(limit).trim() else ""

    private fun reject(reason: String): Nothing =
        throw ResponseStatusException(HttpStatus.BAD_REQUEST, reason)
}

@org.springframework.web.bind.annotation.RestController
@org.springframework.web.bind.annotation.RequestMapping("/api/v1/catalog")
class CatalogController(private val catalog: ConfigCatalog) {
    @org.springframework.web.bind.annotation.PostMapping("/preview")
    fun preview(@org.springframework.web.bind.annotation.RequestBody body: TextImportRequest): CatalogPreviewResponse =
        catalog.preview(body.content)
}
