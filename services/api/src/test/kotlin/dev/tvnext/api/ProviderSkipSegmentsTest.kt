package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.nio.file.Path
import kotlin.test.*

class ProviderSkipSegmentsTest {
    private val mapper = jacksonObjectMapper()

    @Test fun originalMillisecondsNullableEndingAndMalformedMembersMatchNativeGolden() {
        val fixture = mapper.readTree(Path.of("../../fixtures/fongmi-provider-skips-golden.json").toFile())
        assertEquals(fixture.path("expected"), mapper.valueToTree(ProviderSkipSegments.normalize(fixture.path("input"))))
        for (raw in listOf("null", "{}", "\"[]\"", "42")) {
            assertTrue(ProviderSkipSegments.normalize(mapper.readTree(raw)).isEmpty())
        }
    }

    @Test fun providerOrderAndInspectionOutputAndTimeBoundsAreExplicit() {
        val entries = mapper.createArrayNode()
        repeat(200) { index -> entries.addObject().put("type", "middle").put("start", index).put("end", index + 1) }
        val normalized = ProviderSkipSegments.normalize(entries)
        assertEquals(32, normalized.size)
        assertEquals((0L..31L).toList(), normalized.map { it.startMs })
        val late = mapper.createArrayNode()
        repeat(128) { late.addNull() }
        late.addObject().put("type", "opening").put("start", 0).put("end", 1)
        assertTrue(ProviderSkipSegments.normalize(late).isEmpty())
        assertEquals(604_800_000L, ProviderSkipSegments.normalize(mapper.readTree(
            """[{"type":"middle","start":604799999,"end":604800000}]""")).single().endMs)
    }
}
