package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URI
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class CloudRequest(val server: String = "", val token: String = "", val path: String = "/", val password: String = "", val page: Int = 1)
data class CloudFile(val name: String, val directory: Boolean, val size: Long, val modified: String?)
data class CloudPage(val path: String, val entries: List<CloudFile>, val total: Int, val page: Int, val hasMore: Boolean)
data class CloudPlayback(val url: String, val name: String, val headers: Map<String,String>)

/** AList/OpenList gateway. Tokens stay in request memory; no credential persistence or logging. */
@Service
class CloudDrive(private val mapper: ObjectMapper, private val transport: ProviderTransport) {
    fun list(request: CloudRequest): CloudPage {
        validate(request)
        val data = call(request, "list", mapOf("path" to request.path, "password" to request.password, "page" to request.page, "per_page" to 100, "refresh" to false))
        val content = data.path("content")
        val total = data.path("total").asInt(0).coerceIn(0,10_000_000)
        return CloudPage(request.path, content.take(100).mapNotNull { node ->
            val name = node.path("name").asText("")
            if (name.isBlank() || name.length > 500 || name in listOf(".","..") || name.contains('/')) null
            else CloudFile(name,node.path("is_dir").asBoolean(false),node.path("size").asLong(0).coerceAtLeast(0),node.path("modified").asText("").ifBlank { null })
        }, total, request.page, request.page.toLong()*100 < total)
    }
    fun play(request: CloudRequest): CloudPlayback {
        validate(request)
        val data = call(request,"get",mapOf("path" to request.path,"password" to request.password))
        if (data.path("is_dir").asBoolean()) bad("Select a file")
        val url = data.path("raw_url").asText("")
        Subscriptions.httpUri(url)
        // OpenList fs/get "header" is directory presentation HTML, never HTTP request headers.
        return CloudPlayback(url,data.path("name").asText(request.path.substringAfterLast('/')).take(200),emptyMap())
    }
    private fun call(r: CloudRequest, op: String, body: Map<String,Any>): JsonNode {
        val base = Subscriptions.httpUri(r.server.trimEnd('/') + "/")
        if (base.rawQuery != null) bad("Cloud server URL must not contain query parameters")
        val response = transport.postJson(base.resolve("api/fs/$op"), if (r.token.isBlank()) emptyMap() else mapOf("Authorization" to r.token),mapper.writeValueAsString(body))
        val root = try { mapper.readTree(response) } catch (_: Exception) { bad("Invalid cloud response") }
        if (root?.path("code")?.asInt() != 200) throw ResponseStatusException(HttpStatus.BAD_GATEWAY,"Cloud request rejected; check token and folder password")
        return root.path("data")
    }
    private fun validate(r: CloudRequest) {
        if (r.token.length > 4096 || r.password.length > 500 || r.path.length > 4096 || !r.path.startsWith('/') ||
            r.path.any { it.code < 32 } || r.path.split('/').any { it == "." || it == ".." } || r.page !in 1..1000) bad("Invalid cloud request")
    }
    private fun bad(message: String): Nothing = throw ResponseStatusException(HttpStatus.BAD_REQUEST,message)
}
@RestController
@RequestMapping("/api/v1/cloud")
class CloudDriveController(private val drive: CloudDrive) {
    @PostMapping("/list") fun list(@RequestBody r: CloudRequest) = drive.list(r)
    @PostMapping("/play") fun play(@RequestBody r: CloudRequest) = drive.play(r)
}
