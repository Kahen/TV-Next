import Foundation
import XCTest
@testable import TVNext

final class NativeProviderSkipSegmentsTests: XCTestCase {
    func testMillisecondsInclusiveStartExclusiveEndAndFiniteDuration() {
        let middle = NativeProviderSkipSegment(type: "middle", startMs: 60_000, endMs: 90_500)
        XCTAssertNil(middle.target(current: 59.999, duration: 1200))
        XCTAssertEqual(middle.target(current: 60, duration: 1200), 90.5)
        XCTAssertEqual(middle.target(current: 90.499, duration: 1200), 90.5)
        XCTAssertNil(middle.target(current: 90.5, duration: 1200))
        XCTAssertNil(middle.target(current: 60, duration: 90))
        for duration in [Double.infinity, Double.nan, 0, -1, 604800] {
            XCTAssertNil(middle.target(current: 60, duration: duration))
        }
        for time in [Double.infinity, Double.nan, -1] {
            XCTAssertNil(middle.target(current: time, duration: 1200))
        }
        let ending = NativeProviderSkipSegment(type: "ending", startMs: 1_100_000, endMs: nil)
        XCTAssertEqual(ending.target(current: 1100, duration: 1200), 1200)
        XCTAssertNil(ending.target(current: 1200, duration: 1200))
        XCTAssertFalse(NativeProviderSkipSegment(type: "ending", startMs: 0, endMs: nil).isValid)
        XCTAssertFalse(NativeProviderSkipSegment(type: "opening", startMs: 0, endMs: nil).isValid)
    }

    func testNormalizationPreservesProviderOrderAndStopsAtThirtyTwoUniqueSegments() {
        let first = NativeProviderSkipSegment(type: "opening", startMs: 0, endMs: 1_000)
        let invalid = NativeProviderSkipSegment(type: "middle", startMs: -1, endMs: 10)
        let valid = (0..<40).map { index in
            NativeProviderSkipSegment(type: "middle",
                                      startMs: Int64(index + 1) * 2_000,
                                      endMs: Int64(index + 1) * 2_000 + 1_000)
        }
        let normalized = NativeProviderSkipSegment.normalized([invalid, first, first] + valid)
        XCTAssertEqual(normalized.count, 32)
        XCTAssertEqual(normalized.first, first)
        XCTAssertEqual(normalized[1], valid[0])
        XCTAssertEqual(normalized.last, valid[30])
        XCTAssertEqual(Set(normalized).count, normalized.count)
    }

    func testNormalizationDoesNotInspectValidEntriesAfterFirst128() {
        let invalid = NativeProviderSkipSegment(type: "opening", startMs: -1, endMs: 100)
        let late = NativeProviderSkipSegment(type: "ending", startMs: 500, endMs: nil)
        XCTAssertEqual(NativeProviderSkipSegment.normalized(Array(repeating: invalid, count: 128) + [late]), [])
        XCTAssertEqual(NativeProviderSkipSegment.normalized(Array(repeating: invalid, count: 127) + [late]), [late])
    }

    func testDecoderStopsAtThirtyTwoUniqueValidHintsAndPreservesOrder() throws {
        let hints = (0..<32).map { index in
            #"{"type":"middle","startMs":\#(index * 1000),"endMs":\#(index * 1000 + 500)}"#
        }
        let late = #"{"type":"ending","startMs":32000}"#
        let raw = "[" + (["null", hints[0], hints[0]] + hints + [late]).joined(separator: ",") + "]"
        let parsed = try JSONDecoder().decode(NativeProviderSkipSegments.self, from: Data(raw.utf8))
        XCTAssertEqual(parsed.values.count, 32)
        XCTAssertEqual(parsed.values.first?.startMs, 0)
        XCTAssertEqual(parsed.values.last?.startMs, 31_000)
        XCTAssertFalse(parsed.values.contains { $0.type == "ending" })
    }

    func testDecoderStillInspectsThrough128WhenQuotaNotReached() throws {
        let valid = #"{"type":"opening","startMs":0,"endMs":1000}"#
        let raw = "[" + (Array(repeating: "null", count: 127) + [valid, valid]).joined(separator: ",") + "]"
        let parsed = try JSONDecoder().decode(NativeProviderSkipSegments.self, from: Data(raw.utf8))
        XCTAssertEqual(parsed.values, [NativeProviderSkipSegment(type: "opening", startMs: 0, endMs: 1000)])
    }

    func testMalformedOptionalMetadataDoesNotBreakPlaybackDecoding() throws {
        let prefix = "\"url\":\"https://example.invalid/owned.mp4\",\"name\":\"Owned\",\"lineName\":\"Owned\",\"headers\":{},\"danmaku\":[],\"subtitles\":[]"
        for raw in ["null", "{}", "\"[]\"", "[null,{},4,{\"type\":\"opening\",\"startMs\":true,\"endMs\":5}]"] {
            let playback = try JSONDecoder().decode(NativeMediaPlayback.self,
                from: Data(("{" + prefix + ",\"skipSegments\":" + raw + "}").utf8))
            XCTAssertEqual(playback.skipSegments?.values ?? [], [])
            XCTAssertEqual(playback.name, "Owned")
        }
        let previousServer = try JSONDecoder().decode(NativeMediaPlayback.self, from: Data(("{" + prefix + "}").utf8))
        XCTAssertNil(previousServer.skipSegments)
    }
}
