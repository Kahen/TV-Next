package dev.tvnext.api

import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URI
import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException
import org.springframework.web.servlet.config.annotation.CorsRegistry
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer

@SpringBootApplication
class TvNextApplication

fun main(args: Array<String>) {
    runApplication<TvNextApplication>(*args)
}

data class TextImportRequest(val content: String = "")
data class Channel(val name: String, val url: String, val group: String, val logo: String? = null, val tvgId: String? = null)
data class PlaylistResponse(val channels: List<Channel>, val total: Int = channels.size)
data class SitePreview(val key: String, val name: String, val type: Int?)
data class ConfigPreviewResponse(val spiderDeclared: Boolean, val sites: List<SitePreview>, val liveGroupCount: Int)

@Service
class PlaylistParser {
    companion object {
        const val MAX_CHARS = 1_048_576
        const val MAX_LINES = 20_000
        const val MAX_CHANNELS = 5_000
        private val attribute = Regex("([A-Za-z0-9_-]+)\\s*=\\s*\"([^\"]*)\"")
    }

    private fun metadataTitle(line: String): String? {
        var quoted = false
        for (index in line.indices) {
            when (line[index]) {
                '"' -> quoted = !quoted
                ',' -> if (!quoted) return line.substring(index + 1).trim()
            }
        }
        return null
    }

    private fun safeHttpUri(value: String): URI? {
        if (value.length > 2048 || value != value.trim() ||
            value.any { it.code < 0x20 || it.code == 0x7f }) return null
        val uri = runCatching { URI(value) }.getOrNull() ?: return null
        return uri.takeIf {
            it.scheme?.lowercase() in setOf("http", "https") &&
                !it.host.isNullOrBlank() && it.rawUserInfo == null
        }
    }

    fun parse(content: String): PlaylistResponse {
        validateSize(content)
        val channels = mutableListOf<Channel>()
        var name: String? = null
        var group = "Uncategorized"
        var logo: String? = null
        var tvgId: String? = null
        var lines = 0
        content.lineSequence().forEach { raw ->
            lines++
            if (lines > MAX_LINES) fail("Too many lines")
            val line = raw.trim()
            when {
                line.startsWith("#EXTINF", ignoreCase = true) -> {
                    val attrs = attribute.findAll(line).associate { it.groupValues[1].lowercase() to it.groupValues[2] }
                    name = metadataTitle(line)?.takeIf { it.isNotEmpty() }
                        ?: attrs["tvg-name"]?.takeIf { it.isNotBlank() } ?: "Unnamed"
                    group = attrs["group-title"]?.takeIf { it.isNotBlank() } ?: "Uncategorized"
                    logo = attrs["tvg-logo"]?.takeIf { safeHttpUri(it) != null }
                    tvgId = attrs["tvg-id"]?.takeIf { it.isNotBlank() }
                }
                line.startsWith("#EXTGRP:", ignoreCase = true) -> {
                    group = line.substringAfter(":").trim().ifBlank { "Uncategorized" }
                }
                line.isEmpty() || line.startsWith("#") -> Unit
                else -> {
                    val uri = safeHttpUri(line)
                    if (uri != null) {
                        if (channels.size >= MAX_CHANNELS) fail("Too many channels")
                        channels += Channel(name?.take(200) ?: (uri.host ?: "Stream"),
                            line, group.take(100), logo, tvgId?.take(150))
                    }
                    name = null
                    group = "Uncategorized"
                    logo = null
                    tvgId = null
                }
            }
        }
        return PlaylistResponse(channels)
    }
}

@Service
class ConfigInspector(private val mapper: ObjectMapper) {
    fun inspect(content: String): ConfigPreviewResponse {
        validateSize(content)
        val root = try { mapper.readTree(content) } catch (_: Exception) { fail("Invalid JSON configuration") }
        if (root == null || !root.isObject) fail("Expected JSON object")
        val sites = root.path("sites")
        val lives = root.path("lives")
        if (!sites.isMissingNode && !sites.isArray) fail("sites must be an array")
        if (!lives.isMissingNode && !lives.isArray) fail("lives must be an array")
        val preview = sites.take(1000).filter { it.isObject }.map {
            SitePreview(it.path("key").asText("").take(200), it.path("name").asText("").take(200),
                if (it.path("type").isInt) it.path("type").asInt() else null)
        }
        return ConfigPreviewResponse(
            spiderDeclared = root.path("spider").asText("").isNotBlank(),
            sites = preview,
            liveGroupCount = if (lives.isArray) lives.size() else 0
        )
    }
}

private fun validateSize(content: String) {
    if (content.isBlank() || content.length > PlaylistParser.MAX_CHARS ||
        content.toByteArray(Charsets.UTF_8).size > PlaylistParser.MAX_CHARS) {
        fail("Text must be 1..1048576 UTF-8 bytes")
    }
}

private fun fail(message: String): Nothing = throw ResponseStatusException(HttpStatus.BAD_REQUEST, message)

@RestController
@RequestMapping("/api/v1")
class ImportController(private val playlists: PlaylistParser, private val configs: ConfigInspector) {
    @GetMapping("/health")
    fun health() = mapOf("status" to "ok", "service" to "tv-next-api")

    @PostMapping("/playlists/parse")
    fun parsePlaylist(@RequestBody request: TextImportRequest) = playlists.parse(request.content)

    @PostMapping("/configs/inspect")
    fun inspectConfig(@RequestBody request: TextImportRequest) = configs.inspect(request.content)
}

@RestControllerAdvice
class ApiErrorHandler {
    @ExceptionHandler(ResponseStatusException::class)
    fun handle(error: ResponseStatusException): ResponseEntity<Map<String, String>> =
        ResponseEntity.status(error.statusCode).body(mapOf("error" to (error.reason ?: "Request rejected")))

    @ExceptionHandler(org.springframework.http.converter.HttpMessageNotReadableException::class)
    fun malformed(): ResponseEntity<Map<String, String>> =
        ResponseEntity.status(HttpStatus.BAD_REQUEST).body(mapOf("error" to "Invalid request JSON"))
}

@Configuration
class ApiCors : WebMvcConfigurer {
    override fun addCorsMappings(registry: CorsRegistry) {
        val origins = System.getenv("TV_NEXT_CORS_ALLOWED_ORIGINS")
            ?.split(",")?.map { it.trim() }
            ?.filter { it.startsWith("http://") || it.startsWith("https://") }
            ?.takeIf { it.isNotEmpty() }
            ?: listOf("http://localhost:5173", "http://127.0.0.1:5173")
        registry.addMapping("/api/**").allowedOrigins(*origins.toTypedArray())
            .allowedMethods("GET", "POST", "OPTIONS").allowedHeaders("Content-Type")
    }
}
