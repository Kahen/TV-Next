package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class LiveTimeshift(val url: String, val start: Long, val window: Long)
data class LiveCatchup(val type: String = "append", val days: String = "7", val source: String = "",
    val regex: String = "", val replace: String = "")
data class LiveReplayRequest(val channel: Channel, val time: Long = 0, val stop: Long? = null, val timezone: String = "UTC")
data class LiveReplaySession(val path: String, val expiresAt: Long, val hls: Boolean, val time: Long)

/** FongMi TimeshiftPlayback fetches a Result, whereas Catchup formats a media URL. */
@Service
class LiveReplay(private val mapper: ObjectMapper, private val transport: ProviderTransport) {
    fun resolve(r: LiveReplayRequest, now: Long = System.currentTimeMillis()): MediaRelayRequest {
        Subscriptions.httpUri(r.channel.url)
        ProviderTransport.validateHeaders(r.channel.headers)
        val shift = r.channel.timeshift
        if (shift != null && r.stop == null) {
            val endpoint = timeshiftUrl(shift, r.time, now)
            // The original timeshift RPC does not inherit the playing stream's credentials.
            val root = try { mapper.readTree(transport.get(Subscriptions.httpUri(endpoint))) }
                catch (e: ResponseStatusException) { throw e }
                catch (_: Exception) { fail("Invalid timeshift Result", HttpStatus.BAD_GATEWAY) }
            if (root == null || !root.isObject || root.path("parse").asInt(0) != 0 ||
                root.path("jx").asInt(0) != 0 || root.path("playUrl").asText("").isNotBlank() ||
                root.path("msg").asText("").isNotBlank() || !root.path("drm").isMissingNode && !root.path("drm").isNull)
                fail("Timeshift requires an unsupported parser or DRM", HttpStatus.UNPROCESSABLE_ENTITY)
            val url = root.path("url").takeIf { it.isTextual }?.asText()
                ?: fail("Timeshift Result must contain a direct URL", HttpStatus.BAD_GATEWAY)
            Subscriptions.httpUri(url)
            var header = root.path("header")
            if (header.isTextual) header = try { mapper.readTree(header.asText()) ?: fail("Invalid timeshift headers", HttpStatus.BAD_GATEWAY) }
                catch (_: Exception) { fail("Invalid timeshift headers", HttpStatus.BAD_GATEWAY) }
            if (!header.isMissingNode && !header.isNull && !header.isObject) fail("Invalid timeshift headers", HttpStatus.BAD_GATEWAY)
            val headers = if (header.isObject) header.fields().asSequence().associate { it.key to it.value.asText() } else emptyMap()
            ProviderTransport.validateHeaders(headers)
            return MediaRelayRequest(url, headers)
        }
        if (r.time == 0L && r.stop == null) return MediaRelayRequest(r.channel.url, r.channel.headers)
        val catchup = r.channel.catchup ?: fail("This channel does not declare programme catchup", HttpStatus.UNPROCESSABLE_ENTITY)
        return MediaRelayRequest(catchupUrl(r.channel.url, catchup, r.time, r.stop ?: now, r.timezone, now), r.channel.headers)
    }

    companion object {
        private val timeToken = Regex("\\{time\\}|%7Btime%7D", RegexOption.IGNORE_CASE)
        private val catchupToken = Regex("\\$?\\{([^{}]+)}")
        private const val DAY = 86_400_000L

        internal fun timeshiftUrl(s: LiveTimeshift, time: Long, now: Long): String {
            if (s.url.length > 2048 || !timeToken.containsMatchIn(s.url) || s.start <= 0 || s.start >= now || s.window <= 0)
                fail("Invalid timeshift declaration")
            val lower = maxOf(s.start, now - s.window)
            if (time != 0L && time !in lower..now) fail("Replay time is outside the provider window")
            return timeToken.replace(s.url, time.toString()).also { Subscriptions.httpUri(it) }
        }

        internal fun catchupUrl(live: String, c: LiveCatchup, start: Long, stop: Long, timezone: String, now: Long): String {
            val days = c.days.toIntOrNull()?.takeIf { it in 1..30 } ?: fail("Catchup days must be 1..30")
            if (start <= 0 || start < now - days * DAY || start >= stop || stop > now) fail("Programme is outside the catchup window")
            if (c.type !in setOf("default", "append") || c.source.isBlank() || c.source.length > 2048)
                fail("Unsupported catchup mode", HttpStatus.UNPROCESSABLE_ENTITY)
            if (timezone.length > 80) fail("Invalid catchup timezone")
            val zone = runCatching { ZoneId.of(timezone) }.getOrElse { fail("Invalid catchup timezone") }
            // Deliberately restrict regex/replacement to literals: never execute provider regular expressions.
            if (c.regex.length > 200 || c.regex.any { it in "[](){}*+?^$|\\" } || c.regex.isNotEmpty() && !live.contains(c.regex))
                fail("Unsupported catchup match", HttpStatus.UNPROCESSABLE_ENTITY)
            var base = live
            if (c.replace.isNotEmpty()) {
                val pair = c.replace.split(',', limit = 2)
                if (pair.size != 2 || pair[0].isEmpty() || c.replace.length > 400 || pair.any { p -> p.any { it in "[](){}*+?^$|\\" } })
                    fail("Unsupported catchup replacement", HttpStatus.UNPROCESSABLE_ENTITY)
                base = base.replace(pair[0], pair[1])
            }
            val source = catchupToken.replace(c.source) { match ->
                val tag = match.groupValues[1]
                when {
                    tag.startsWith("utcend:") -> (stop / 1000).toString()
                    tag.startsWith("utc:") -> (start / 1000).toString()
                    tag.startsWith("(b)") || tag.startsWith("(e)") -> {
                        var pattern = tag.substring(3)
                        val utc = pattern.endsWith("|UTC")
                        if (utc) pattern = pattern.removeSuffix("|UTC")
                        val millis = if (tag.startsWith("(b)")) start else stop
                        if (pattern == "timestamp") (millis / 1000).toString()
                        else {
                            if (pattern !in setOf("yyyyMMddHHmmss", "yyyyMMdd", "yyyy-MM-dd", "HHmmss", "HH:mm:ss"))
                                fail("Unsupported catchup time format", HttpStatus.UNPROCESSABLE_ENTITY)
                            DateTimeFormatter.ofPattern(pattern, Locale.ROOT).withZone(if (utc) ZoneId.of("UTC") else zone)
                                .format(Instant.ofEpochMilli(millis))
                        }
                    }
                    else -> fail("Unsupported catchup token", HttpStatus.UNPROCESSABLE_ENTITY)
                }
            }
            if (source.contains('{') || source.contains('}') || Regex("%7[BD]", RegexOption.IGNORE_CASE).containsMatchIn(source))
                fail("Unresolved catchup template")
            val result = if (c.type == "default") source else base + if (java.net.URI(base).rawQuery != null) source.replace("?", "&") else source
            Subscriptions.httpUri(result)
            // A programme URL on another origin must not receive the live stream's credentials.
            if (mediaOrigin(Subscriptions.httpUri(result)) != mediaOrigin(Subscriptions.httpUri(live)))
                fail("Cross-origin catchup is unsupported", HttpStatus.UNPROCESSABLE_ENTITY)
            return result
        }

        internal fun timeshift(node: JsonNode, mapper: ObjectMapper): LiveTimeshift? =
            node.takeIf { it.isObject && it.path("start").isIntegralNumber && it.path("start").canConvertToLong() &&
                it.path("window").isIntegralNumber && it.path("window").canConvertToLong() && it.path("url").isTextual }
                ?.let { runCatching { mapper.treeToValue(it, LiveTimeshift::class.java) }.getOrNull() }
        internal fun catchup(node: JsonNode, mapper: ObjectMapper): LiveCatchup? =
            node.takeIf { it.isObject }?.let { runCatching { mapper.treeToValue(it, LiveCatchup::class.java) }.getOrNull() }?.takeIf { it.source.isNotBlank() }
        private fun fail(message: String, status: HttpStatus = HttpStatus.BAD_REQUEST): Nothing = throw ResponseStatusException(status, message)
    }
}

@RestController
@RequestMapping("/api/v1/subscriptions")
class LiveReplayController(private val accounts: HomeAccounts, private val replay: LiveReplay, private val relay: MediaRelay) {
    @PostMapping("/replay")
    fun replay(@RequestHeader("Authorization", required = false) auth: String?, @RequestBody r: LiveReplayRequest, response: jakarta.servlet.http.HttpServletResponse): LiveReplaySession {
        response.setHeader("Cache-Control", "no-store, private")
        val principal = accounts.principal(auth) // Authorize before provider I/O.
        val media = replay.resolve(r)
        val result = relay.create(principal, media)
        return LiveReplaySession(result.path, result.expiresAt, java.net.URI(media.url).path.lowercase().endsWith(".m3u8"), r.time)
    }
}
