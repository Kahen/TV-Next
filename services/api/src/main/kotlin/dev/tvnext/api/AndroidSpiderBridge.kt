package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.node.ObjectNode
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.Semaphore
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.stereotype.Service
import org.springframework.web.server.ResponseStatusException

/** Exact init binding. Never derived from a requested command, image or classpath. */
data class SpiderSpec(val key: String, val api: String, val jar: String, val ext: String, val flags: List<String>) {
    fun fingerprint(): String {
        val digest = MessageDigest.getInstance("SHA-256")
        (listOf(key, api, jar, ext, flags.size.toString()) + flags).forEach {
            val bytes = it.toByteArray(Charsets.UTF_8)
            digest.update("${bytes.size}:".toByteArray(Charsets.US_ASCII))
            digest.update(bytes)
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    companion object {
        fun from(site: JsonNode, inheritedJar: String = "", flags: JsonNode? = null): SpiderSpec = SpiderSpec(
            site.path("key").asText(""), site.path("api").asText(""), site.path("jar").asText("").ifBlank { inheritedJar },
            site.path("ext").let { if (it.isContainerNode) it.toString() else it.asText("").trim() },
            flags?.takeIf { it.isArray }?.map { it.asText() }.orEmpty()
        )
    }
}

/** Administrator opt-in, disabled by default. A supplied subscription is not execution permission. */
@Component
class SpiderPolicy(
    @Value("\${TV_NEXT_SPIDER_ANDROID_URL:}") address: String = "",
    @Value("\${TV_NEXT_SPIDER_BINDINGS:}") bindings: String = ""
) {
    val endpoint: URI? = address.takeIf { it.isNotBlank() }?.let {
        val uri = Subscriptions.httpUri(it)
        require(uri.rawQuery == null && uri.rawPath.orEmpty() in listOf("", "/")) { "Spider host must be an origin" }
        uri.resolve("/spider-api")
    }
    private val approved = bindings.split(',').filter { it.isNotBlank() }.map { it.trim().lowercase() }.toSet().also {
        require(it.size <= 100 && it.all { hash -> hash.matches(Regex("[a-f0-9]{64}")) }) { "Invalid Spider bindings" }
    }
    fun allows(spec: SpiderSpec): Boolean = endpoint != null &&
        spec.api.matches(Regex("csp_[A-Za-z_$][A-Za-z0-9_$]{0,199}")) &&
        spec.jar.matches(Regex("https?://[^;]+;md5;[a-fA-F0-9]{32}")) &&
        spec.ext.toByteArray(Charsets.UTF_8).size <= 65_536 && spec.flags.size <= 100 &&
        spec.flags.all { it.length <= 200 } && spec.fingerprint() in approved
}

/**
 * Bounded adapter to original FongMi SpiderTest/SpiderTestSession on a separate
 * Android host. DEX/native code never loads in Spring, the browser or iOS.
 * This is an experimental stateless bridge, not a Docker sandbox replacement.
 */
@Service
class AndroidSpiderBridge(private val mapper: ObjectMapper, private val transport: ProviderTransport, private val policy: SpiderPolicy) {
    private val permits = Semaphore(2)
    internal var nanoTime: () -> Long = System::nanoTime
    internal var pause: () -> Unit = { Thread.sleep(100) }

    fun invoke(spec: SpiderSpec, op: String, request: SiteRequest, extra: Map<String,String> = emptyMap(), requestDeadline: Long = Long.MAX_VALUE): JsonNode {
        if (op !in setOf("home", "category", "search", "detail", "play")) fail("Unsupported Spider method", HttpStatus.UNPROCESSABLE_ENTITY)
        if (!policy.allows(spec)) fail("Spider binding is not enabled on this server", HttpStatus.UNPROCESSABLE_ENTITY)
        if (Thread.currentThread().isInterrupted) fail("Spider request cancelled", HttpStatus.REQUEST_TIMEOUT)
        if (!permits.tryAcquire()) fail("Spider concurrency limit", HttpStatus.TOO_MANY_REQUESTS)
        val endpoint = requireNotNull(policy.endpoint)
        val deadline = minOf(nanoTime() + 15_000_000_000L, requestDeadline)
        var session: String? = null
        fun headers() = session?.let { mapOf("X-Spider-Session" to it) }.orEmpty()
        fun exchange(path: String, method: String, payload: Any? = null): JsonNode {
            if (Thread.currentThread().isInterrupted || nanoTime() >= deadline)
                fail("Spider request timed out or cancelled", HttpStatus.GATEWAY_TIMEOUT)
            val raw = transport.bridgeRequest(URI(endpoint.toString() + path), headers(), payload?.let(mapper::writeValueAsString), method, deadline)
            val root = runCatching { mapper.reader().with(DeserializationFeature.FAIL_ON_TRAILING_TOKENS).readTree(raw) }.getOrNull()
            if (root?.isObject != true) fail("Invalid Spider host response")
            return root
        }
        fun await(initial: JsonNode, terminal: String): JsonNode {
            var snapshot = initial
            while (snapshot.path("state").asText() in setOf("loading", "running")) {
                pause()
                snapshot = exchange("", "GET")
            }
            if (snapshot.path("state").asText() != terminal) fail("Spider operation failed")
            return snapshot
        }
        fun run(method: String, args: List<Any>, allowEmpty: Boolean = false): JsonNode {
            val snapshot = await(exchange("/run", "POST", mapOf("method" to method, "args" to args, "timeout" to 8)), "done")
            val output = snapshot.path("result").takeIf { it.isTextual }?.asText() ?: fail("Invalid Spider result")
            if (allowEmpty && output.isBlank()) return mapper.createObjectNode()
            val root = runCatching { mapper.reader().with(DeserializationFeature.FAIL_ON_TRAILING_TOKENS).readTree(output) }.getOrNull()
            if (root?.isObject != true) fail("Invalid Spider result JSON")
            return root
        }
        try {
            session = exchange("", "POST", emptyMap<String,String>()).path("session").asText().also {
                if (!it.matches(Regex("[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}"))) fail("Invalid Spider host session")
            }
            val loaded = await(exchange("/load", "POST", mapOf("api" to spec.api, "ext" to spec.ext, "jar" to spec.jar, "timeout" to 8)), "loaded")
            if (!loaded.path("loaded").asBoolean(false)) fail("Spider host did not load provider")
            return when (op) {
                "home" -> {
                    val root = run("home", listOf(true))
                    if (root.path("list").isMissingNode || root.path("list").isEmpty) {
                        val videos = run("homeVod", emptyList(), true)
                        if (videos.path("list").isArray) (root as ObjectNode).set<JsonNode>("list", videos.path("list"))
                    }
                    root
                }
                "category" -> run("category", listOf(requireNotNull(request.categoryId), request.page.toString(), true, request.filters))
                "search" -> run("search", listOf(requireNotNull(request.query).trim(), request.quick, request.page.toString()))
                "detail" -> run("detail", listOf(listOf(requireNotNull(request.vodId))))
                "play" -> run("play", listOf(requireNotNull(extra["flag"]), requireNotNull(extra["play"]), spec.flags))
                // Interactive/action side effects require a separate permission/UI contract.
                else -> fail("Unsupported Spider method", HttpStatus.UNPROCESSABLE_ENTITY)
            }
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            fail("Spider request cancelled", HttpStatus.REQUEST_TIMEOUT)
        } catch (error: ResponseStatusException) { throw error }
        catch (_: Exception) { fail("Spider host transport failed") }
        finally {
            val interrupted = Thread.interrupted()
            try {
                // DELETE closes the upstream runtime, cancels tasks and releases its
                // downloaded JAR. It must run after success, errors and interruption.
                if (session != null) runCatching {
                    transport.bridgeRequest(endpoint, headers(), null, "DELETE", System.nanoTime() + 2_000_000_000L)
                }
            } finally { permits.release(); if (interrupted) Thread.currentThread().interrupt() }
        }
    }
    private fun fail(message: String, status: HttpStatus = HttpStatus.BAD_GATEWAY): Nothing = throw ResponseStatusException(status, message)
}
