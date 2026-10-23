package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import com.fasterxml.jackson.databind.node.ArrayNode
import java.net.URI
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class SubscriptionRequest(val content: String = "", val url: String = "")
data class SubscriptionSite(val key: String, val name: String, val type: Int, val api: String, val ext: String,
    val jar: String, val searchable: Boolean, val quickSearch: Boolean, val changeable: Boolean,
    val hidden: Boolean, val categories: List<String>, val support: String)
data class SubscriptionDepot(val name: String, val url: String)
data class SubscriptionDocument(val content: String, val url: String, val sites: List<SubscriptionSite>,
    val depots: List<SubscriptionDepot>, val liveCount: Int, val warnings: List<String>)

/** Port of Decoder/VodConfig/Site/ExtAdapter semantics from Kahen/TV release 0af3b31 (GPL-3.0). */
@Service
class Subscriptions(private val mapper: ObjectMapper, private val transport: ProviderTransport) {
    fun load(request: SubscriptionRequest): SubscriptionDocument {
        var base = request.url.takeIf { it.isNotBlank() }?.let { httpUri(it) }
        val text = if (request.content.isNotBlank()) request.content else {
            if (base == null) bad("Provide subscription URL or content")
            val fetched=transport.getDocument(base)
            base=fetched.uri
            fetched.content
        }
        val root = try { mapper.readTree(decode(text)) } catch (e: ResponseStatusException) { throw e }
            catch (_: Exception) { bad("Invalid subscription JSON") }
        if (root == null || !root.isObject) bad("Expected subscription object")
        if (root.has("msg")) bad(root.path("msg").asText("Subscription returned an error").take(200))
        resolveNode(root, base)
        val warnings = mutableListOf<String>()
        val spider = root.path("spider").asText("")
        if (spider.length > 8192) bad("Spider reference exceeds limit")
        val keys = mutableSetOf<String>()
        if (root.path("sites").size() > 1000 || root.path("urls").size() > 100) bad("Subscription exceeds limits")
        val sites = root.path("sites").takeIf { it.isArray }?.mapNotNull { node ->
            val key = node.path("key").asText("")
            if (key.isBlank() || !keys.add(key)) return@mapNotNull null
            if (key.length > 200 || node.path("api").asText("").length > 4096 || node.path("jar").asText("").length > 8192) bad("Site field exceeds limit")
            val type = node.path("type").asInt(0)
            val ext = node.path("ext").let { if (it.isObject || it.isArray) it.toString() else it.asText("").trim() }
            SubscriptionSite(key.take(200), node.path("name").asText(key).take(200), type, node.path("api").asText(""), ext,
                node.path("jar").asText("").ifBlank { spider }, node.path("searchable").asInt(1) == 1,
                node.path("quickSearch").asInt(1) == 1, node.path("changeable").asInt(1) == 1,
                node.path("hide").asInt(0) == 1, node.path("categories").take(100).map { it.asText().take(150) },
                when(type) { 0 -> "xml-api"; 1, 2 -> "json-api"; 4 -> "http-spider"; 3 -> "requires-spider-runtime"; else -> "unsupported-type" })
        }.orEmpty()
        if (sites.any { it.type == 3 }) warnings += "Type 3 requires a compatible server Spider runtime; metadata import does not execute its JAR/JS/Python."
        if (root.has("parses")) warnings += "Parser definitions preserved; Android WebView sniffing needs an adapter."
        val depots = root.path("urls").takeIf { it.isArray }?.mapNotNull {
            val url = it.path("url").asText("")
            if (runCatching { httpUri(url) }.isFailure) null else SubscriptionDepot(it.path("name").asText(url).take(200), url)
        }.orEmpty()
        val document = SubscriptionDocument(root.toString(), base?.toString().orEmpty(), sites, depots,
            root.path("lives").takeIf { it.isArray }?.size() ?: 0, warnings)
        if (mapper.writeValueAsBytes(document).size > 3_145_728) bad("Normalized subscription response exceeds 3 MiB")
        return document
    }
    fun site(content: String, base: String, key: String): JsonNode {
        val doc = load(SubscriptionRequest(content, base))
        return mapper.readTree(doc.content).path("sites").firstOrNull { it.path("key").asText() == key }
            ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "Unknown subscription site")
    }
    internal fun decode(raw: String): String {
        if (raw.toByteArray(Charsets.UTF_8).size > 1_048_576) bad("Subscription exceeds 1 MiB")
        var data = raw.trim().removePrefix("\uFEFF")
        if (data.startsWith("{")) return data
        val marker = Regex("[A-Za-z0-9]{8}\\*\\*").find(data)
        if (marker != null) data = try { String(Base64.getMimeDecoder().decode(data.substring(marker.range.last + 1)), Charsets.UTF_8) }
            catch (_: Exception) { bad("Invalid subscription base64") }
        if (data.startsWith("2423")) data = try {
            val hex = data.replace(Regex("\\s+"), "")
            require(hex.length % 2 == 0)
            val decoded = String(hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray(), Charsets.UTF_8).lowercase()
            val key = decoded.substringAfter("$#").substringBefore("#$").also { require(it.length <= 16) }.padEnd(16, '0')
            val iv = decoded.takeLast(13).padEnd(16, '0')
            val cipherHex = hex.substring(hex.indexOf("2324") + 4, hex.length - 26)
            val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key.toByteArray(Charsets.UTF_8), "AES"), IvParameterSpec(iv.toByteArray(Charsets.UTF_8)))
            String(cipher.doFinal(cipherHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()), Charsets.UTF_8)
        } catch (_: Exception) { bad("Invalid encrypted subscription") }
        if (data.toByteArray(Charsets.UTF_8).size > 1_048_576) bad("Decoded subscription exceeds limit")
        return data
    }
    private fun resolveNode(node: JsonNode, base: URI?, depth: Int = 0) {
        if (depth > 40) bad("Subscription nesting limit")
        when {
            node.isObject -> (node as ObjectNode).fields().asSequence().toList().forEach { (key, value) ->
                if (value.isTextual && base != null && value.asText().let { it.startsWith("./") || it.startsWith("../") || it.startsWith("//") })
                    node.put(key, base.resolve(value.asText()).toString())
                else resolveNode(value, base, depth + 1)
            }
            node.isArray -> (node as ArrayNode).forEachIndexed { index, value ->
                if (value.isTextual && base != null && value.asText().let { it.startsWith("./") || it.startsWith("../") || it.startsWith("//") })
                    node.set(index,mapper.nodeFactory.textNode(base.resolve(value.asText()).toString()))
                else resolveNode(value,base,depth+1)
            }
        }
    }
    companion object {
        internal fun httpUri(value: String): URI {
            val uri = runCatching { URI(value) }.getOrElse { bad("Invalid HTTP(S) address") }
            if (value.length > 4096 || value.any { it.code <= 32 || it.code == 127 } || uri.scheme !in setOf("http", "https") ||
                uri.host.isNullOrBlank() || uri.rawUserInfo != null || uri.rawFragment != null || uri.port !in -1..65535 || uri.port == 0) bad("Invalid HTTP(S) address")
            return uri
        }
        private fun bad(message: String): Nothing = throw ResponseStatusException(HttpStatus.BAD_REQUEST, message)
    }
}
@RestController
@RequestMapping("/api/v1/subscriptions")
class SubscriptionController(private val subscriptions: Subscriptions) {
    @PostMapping("/load") fun load(@RequestBody r: SubscriptionRequest) = subscriptions.load(r)
}
