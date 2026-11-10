import Foundation
import XCTest
@testable import TVNext

final class NativeProviderSkipSegmentsTests: XCTestCase {
    func testAutomaticPolicyRequiresPlayingAndAttemptsEachSegmentOnlyOnce() {
        let opening = NativeProviderSkipSegment(type: "opening", startMs: 0, endMs: 10_250)
        var state = NativeAutomaticProviderSkipState()
        XCTAssertNil(state.target(segments: [opening], current: 0, duration: 120, playing: false))
        XCTAssertEqual(state.target(segments: [opening], current: 0.5, duration: 120, playing: true), 10.25)
        XCTAssertNil(state.target(segments: [opening], current: 10.25, duration: 120, playing: true))
        XCTAssertNil(state.target(segments: [opening], current: 1, duration: 120, playing: true))
        XCTAssertNil(state.target(segments: [opening], current: 2, duration: 120, playing: true))
    }

    func testReenableRebasesElapsedTimeWithoutConsumingUpcomingRange() {
        let upcoming = NativeProviderSkipSegment(type: "middle", startMs: 20_000, endMs: 30_000)
        var state = NativeAutomaticProviderSkipState()
        XCTAssertNil(state.target(segments: [upcoming], current: 1, duration: 120, playing: true))
        // Playback advances while automation is disabled; enabling must not
        // interpret that gap as a user seek or suppress the next source range.
        state.rebaseClock(to: 19.5, duration: 120)
        XCTAssertNil(state.target(segments: [upcoming], current: 19.5, duration: 120, playing: true))
        XCTAssertEqual(state.target(segments: [upcoming], current: 20, duration: 120, playing: true), 30)
        state.rebaseClock(to: 20, duration: 120)
        XCTAssertNil(state.target(segments: [upcoming], current: 20, duration: 120, playing: true),
                     "Re-enabling must not re-arm an already consumed segment")
    }

    func testAutomaticPolicyPreservesOverlapOrderAndEndingToEOF() {
        let first = NativeProviderSkipSegment(type: "middle", startMs: 10_000, endMs: 20_000)
        let second = NativeProviderSkipSegment(type: "middle", startMs: 15_000, endMs: 25_000)
        let ending = NativeProviderSkipSegment(type: "ending", startMs: 25_000, endMs: nil)
        var state = NativeAutomaticProviderSkipState()
        let hints = [first, second, ending]
        XCTAssertEqual(state.target(segments: hints, current: 16, duration: 30, playing: true), 20)
        XCTAssertEqual(state.target(segments: hints, current: 20, duration: 30, playing: true), 25)
        XCTAssertEqual(state.target(segments: hints, current: 25, duration: 30, playing: true), 30)
        XCTAssertNil(state.target(segments: hints, current: 30, duration: 30, playing: true))
    }

    func testAutomaticPolicyHonorsExplicitAndDiscontinuousSeeksIncludingWhilePaused() {
        let middle = NativeProviderSkipSegment(type: "middle", startMs: 20_000, endMs: 30_000)
        var state = NativeAutomaticProviderSkipState()
        XCTAssertNil(state.target(segments: [middle], current: 0, duration: 120, playing: true))
        XCTAssertNil(state.target(segments: [middle], current: 21, duration: 120, playing: false))
        XCTAssertNil(state.target(segments: [middle], current: 22, duration: 120, playing: true))
        state = NativeAutomaticProviderSkipState()
        state.recordExplicitSeek(to: 20, segments: [middle], duration: 120)
        XCTAssertNil(state.target(segments: [middle], current: 20, duration: 120, playing: true))
        // An ordinary continuous crossing still skips the middle segment.
        state = NativeAutomaticProviderSkipState()
        XCTAssertNil(state.target(segments: [middle], current: 19, duration: 120, playing: true))
        XCTAssertEqual(state.target(segments: [middle], current: 20, duration: 120, playing: true), 30)
    }

    func testAutomaticPolicyRejectsInvalidDurationAndClipsItsProcessingBound() {
        let opening = NativeProviderSkipSegment(type: "opening", startMs: 0, endMs: 10_000)
        for duration in [Double.nan, .infinity, 0, -1, 5, 604_800] {
            var state = NativeAutomaticProviderSkipState()
            XCTAssertNil(state.target(segments: [opening], current: 0, duration: duration, playing: true))
        }
        for current in [Double.nan, .infinity, -1, 120] {
            var state = NativeAutomaticProviderSkipState()
            XCTAssertNil(state.target(segments: [opening], current: current, duration: 120, playing: true))
        }
        let later = NativeProviderSkipSegment(type: "middle", startMs: 20_000, endMs: 30_000)
        var state = NativeAutomaticProviderSkipState()
        XCTAssertNil(state.target(segments: Array(repeating: later, count: 32) + [opening],
                                  current: 0, duration: 120, playing: true))
    }

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
