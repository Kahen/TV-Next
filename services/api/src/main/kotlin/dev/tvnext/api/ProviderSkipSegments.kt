package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode

/** FongMi Result.skips uses milliseconds, including a nullable end for ending. */
data class PlaybackSkipSegment(val type: String, val startMs: Long, val endMs: Long?)

object ProviderSkipSegments {
    const val MAX_TIME_MS = 604_800_000L
    const val MAX_SEGMENTS = 32

    fun normalize(raw: JsonNode): List<PlaybackSkipSegment> {
        if (!raw.isArray) return emptyList()
        val seen = mutableSetOf<PlaybackSkipSegment>()
        return raw.asSequence().take(128).mapNotNull { node ->
            if (!node.isObject) return@mapNotNull null
            val type = node.path("type").takeIf { it.isTextual }?.asText()
            if (type !in setOf("opening", "middle", "ending")) return@mapNotNull null
            val start = milliseconds(node.path("start")) ?: return@mapNotNull null
            val endNode = node.path("end")
            val end = if (endNode.isNull || endNode.isMissingNode) null
                else milliseconds(endNode) ?: return@mapNotNull null
            if (end == null && (type != "ending" || start == 0L)) return@mapNotNull null
            if (end != null && end <= start) return@mapNotNull null
            PlaybackSkipSegment(type!!, start, end).takeIf { seen.add(it) }
        }.take(MAX_SEGMENTS).toList()
    }

    private fun milliseconds(node: JsonNode): Long? {
        val value = when {
            node.isIntegralNumber && node.canConvertToLong() -> node.longValue()
            node.isTextual && node.asText().matches(Regex("[0-9]{1,12}")) -> node.asText().toLongOrNull()
            else -> null
        }
        return value?.takeIf { it in 0..MAX_TIME_MS }
    }
}
