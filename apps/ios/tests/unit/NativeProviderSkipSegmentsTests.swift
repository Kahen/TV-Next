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
