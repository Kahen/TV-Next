package dev.tvnext.api

import java.io.StringReader
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.Locale
import javax.xml.XMLConstants
import javax.xml.parsers.SAXParserFactory
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler

data class EpgChannelRequest(val id: String? = null, val name: String = "")
data class EpgGuideRequest(
    val xml: String = "",
    val channels: List<EpgChannelRequest> = emptyList(),
    val at: String? = null,
    val hours: Int = 12
)
data class EpgProgram(
    val start: String,
    val stop: String,
    val title: String,
    val description: String?
)
data class EpgChannelGuide(
    val id: String?,
    val name: String,
    val matchedChannelId: String?,
    val matchType: String,
    val current: EpgProgram?,
    val upcoming: List<EpgProgram>
)
data class EpgGuideResponse(
    val generatedAt: String,
    val until: String,
    val totalChannels: Int,
    val matchedChannels: Int,
    val channels: List<EpgChannelGuide>,
    val warnings: List<String>
)

private data class XmlProgram(val channel: String, val start: Instant, val stop: Instant, val title: String, val description: String?)
private data class XmlFeed(val aliases: Map<String, List<String>>, val programs: List<XmlProgram>, val warnings: List<String>)

/**
 * Parses an explicitly supplied XMLTV document ONLY. XML DTDs and external entities are forbidden;
 * no HTTP requests, scripts, images, or external guides are ever fetched.
 */
@Service
class XmltvGuideService {
    companion object {
        const val MAX_XML_CHARS = 2_097_152
        const val MAX_REQUEST_CHANNELS = 300
        private val timestampFormat = DateTimeFormatter.ofPattern("uuuuMMddHHmmss")
            .withResolverStyle(ResolverStyle.STRICT)
        private val offsetPattern = Regex("[+-](?:\\d{4}|\\d{2}:\\d{2})")
    }

    fun guide(request: EpgGuideRequest): EpgGuideResponse {
        if (request.xml.isBlank() || request.xml.length > MAX_XML_CHARS) fail("XMLTV must be 1..2097152 characters")
        if (request.channels.isEmpty() || request.channels.size > MAX_REQUEST_CHANNELS) {
            fail("Provide 1..300 channels for EPG matching")
        }
        if (request.hours !in 1..72) fail("hours must be between 1 and 72")
        val now = request.at?.let { timestamp ->
            runCatching { OffsetDateTime.parse(timestamp).toInstant() }
                .getOrElse { fail("at must be an ISO-8601 timestamp with timezone") }
        } ?: Instant.now()
        val until = now.plusSeconds(request.hours.toLong() * 3600)
        val feed = parseXml(request.xml)
        val byId = feed.programs.groupBy { it.channel }
        val normalizedAliases = mutableMapOf<String, MutableSet<String>>()
        feed.aliases.forEach { (id, aliases) ->
            aliases.forEach { alias -> normalizedAliases.getOrPut(normalize(alias)) { mutableSetOf() }.add(id) }
        }
        val guides = request.channels.map { requested ->
            val name = requested.name.trim().take(200)
            val explicitId = requested.id?.trim()?.takeIf { it.isNotEmpty() && it.length <= 200 }
            if (name.isBlank() && explicitId == null) fail("Every channel needs a name or tvg-id")
            val matched = if (explicitId != null &&
                (feed.aliases.containsKey(explicitId) || byId.containsKey(explicitId))) {
                explicitId
            } else null
            val possible = normalizedAliases[normalize(name)]
            val viaName = if (matched == null && possible?.size == 1) possible.single() else null
            val found = matched ?: viaName
            val events = found?.let { byId[it] }.orEmpty()
            val current = events.filter { !it.start.isAfter(now) && it.stop.isAfter(now) }
                .maxByOrNull { it.start }
            val upcoming = events.asSequence().filter {
                !it.start.isBefore(now) && it.start.isBefore(until)
            }.sortedBy { it.start }.take(20).map { toProgram(it) }.toList()
            EpgChannelGuide(explicitId, name.ifBlank { explicitId.orEmpty() }, found,
                if (matched != null) "id" else if (viaName != null) "name" else "none",
                current?.let { toProgram(it) }, upcoming)
        }
        return EpgGuideResponse(now.toString(), until.toString(), guides.size,
            guides.count { it.matchedChannelId != null }, guides, feed.warnings)
    }

    private fun toProgram(item: XmlProgram) =
        EpgProgram(item.start.toString(), item.stop.toString(), item.title, item.description)

    private fun normalize(value: String): String =
        value.trim().lowercase(Locale.ROOT).replace(Regex("\\s+"), " ")

    private fun parseXml(xml: String): XmlFeed {
        val parser = try {
            val factory = SAXParserFactory.newInstance()
            factory.isNamespaceAware = false
            factory.isValidating = false
            factory.isXIncludeAware = false
            factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false)
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
            factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
            factory.newSAXParser()
        } catch (_: Exception) {
            throw ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Secure XML parser unavailable")
        }
        val handler = SafeXmltvHandler()
        try {
            parser.parse(InputSource(StringReader(xml)), handler)
        } catch (_: SAXException) {
            fail("Invalid or forbidden XMLTV content")
        } catch (_: Exception) {
            fail("Invalid XMLTV document")
        }
        return XmlFeed(handler.aliases, handler.programs, handler.warnings)
    }

    private fun fail(message: String): Nothing =
        throw ResponseStatusException(HttpStatus.BAD_REQUEST, message)

    private inner class SafeXmltvHandler : DefaultHandler() {
        val aliases = linkedMapOf<String, List<String>>()
        val programs = mutableListOf<XmlProgram>()
        val warnings = mutableListOf<String>()
        private var depth = 0
        private var currentChannel: String? = null
        private val displayNames = mutableListOf<String>()
        private var programChannel: String? = null
        private var programStart: String? = null
        private var programStop: String? = null
        private var title = ""
        private var description: String? = null
        private var field: String? = null
        private val text = StringBuilder()
        private var channelCount = 0
        private var programCount = 0

        override fun startElement(uri: String?, localName: String?, qName: String?, attributes: Attributes) {
            depth++
            if (depth > 20) throw SAXException("XML nesting limit")
            when (qName) {
                "channel" -> if (depth == 2) {
                    channelCount++
                    if (channelCount > 1000 && "channel limit reached" !in warnings) warnings += "channel limit reached"
                    currentChannel = attributes.getValue("id")?.trim()?.take(200)
                    displayNames.clear()
                }
                "programme" -> if (depth == 2) {
                    programCount++
                    if (programCount > 20_000 && "programme limit reached" !in warnings) warnings += "programme limit reached"
                    programChannel = attributes.getValue("channel")?.trim()?.take(200)
                    programStart = attributes.getValue("start")
                    programStop = attributes.getValue("stop")
                    title = ""
                    description = null
                }
                "display-name", "title", "desc" -> if (
                    (currentChannel != null && qName == "display-name" && depth == 3) ||
                    (programChannel != null && qName != "display-name" && depth == 3)
                ) {
                    field = qName
                    text.setLength(0)
                }
            }
        }

        override fun characters(ch: CharArray, start: Int, length: Int) {
            if (field != null && text.length < 3000) text.append(ch, start, minOf(length, 3000 - text.length))
        }

        override fun endElement(uri: String?, localName: String?, qName: String?) {
            if (field == qName) {
                val value = text.toString().trim()
                when (qName) {
                    "display-name" -> if (value.isNotBlank() && displayNames.size < 20) displayNames += value.take(200)
                    "title" -> if (title.isBlank()) title = value.take(300)
                    "desc" -> if (description == null) description = value.take(1500)
                }
                field = null
            }
            if (qName == "channel" && depth == 2) {
                if (channelCount <= 1000) currentChannel?.takeIf { it.isNotBlank() }?.let {
                    aliases[it] = displayNames.toList()
                }
                currentChannel = null
                displayNames.clear()
            }
            if (qName == "programme" && depth == 2) {
                if (programCount <= 20_000 && !programChannel.isNullOrBlank() && title.isNotBlank()) {
                    val start = parseTimestamp(programStart)
                    val stop = parseTimestamp(programStop)
                    if (start != null && stop != null && stop.isAfter(start)) {
                        programs += XmlProgram(programChannel!!, start, stop, title, description)
                    }
                }
                programChannel = null
                programStart = null
                programStop = null
                description = null
                title = ""
            }
            depth--
        }

        private fun parseTimestamp(raw: String?): Instant? {
            val parts = raw?.trim()?.split(Regex("\\s+")) ?: return null
            val time = parts.getOrNull(0) ?: return null
            if (time.length !in listOf(12, 14) || !time.all { it.isDigit() }) return null
            val date = runCatching { LocalDateTime.parse(if (time.length == 12) time + "00" else time, timestampFormat) }
                .getOrNull() ?: return null
            val zone = when (val offset = parts.getOrNull(1)) {
                null, "Z", "z" -> ZoneOffset.UTC
                else -> {
                    if (!offsetPattern.matches(offset)) return null
                    runCatching { ZoneOffset.of(offset) }.getOrNull() ?: return null
                }
            }
            if (parts.size > 2) return null
            return date.atOffset(zone).toInstant()
        }
    }
}

@RestController
@RequestMapping("/api/v1/epg")
class EpgController(private val guide: XmltvGuideService) {
    @PostMapping("/guide")
    fun guide(@RequestBody request: EpgGuideRequest): EpgGuideResponse = guide.guide(request)
}
