import XCTest
@testable import TVNext

final class NativeEpisodeFilterTests: XCTestCase {
    func testEmptyQueryKeepsOriginalPositions() {
        XCTAssertEqual(NativeEpisodeFilter.indices(names: ["第1集", "第2集", "特别篇"], query: "  "), [0, 1, 2])
    }

    func testFilteringReturnsOriginalIndicesNotFilteredOffsets() {
        XCTAssertEqual(NativeEpisodeFilter.indices(names: ["Pilot", "Bonus", "PILOT 2", "Final"], query: "pilot"), [0, 2])
    }

    func testUnicodeAndDiacriticMatching() {
        XCTAssertEqual(NativeEpisodeFilter.indices(names: ["第1集", "Épisode 2", "第12集"], query: "第1"), [0, 2])
        XCTAssertEqual(NativeEpisodeFilter.indices(names: ["Épisode 2"], query: "episode"), [0])
    }

    func testNoMatchAndEmptyLine() {
        XCTAssertEqual(NativeEpisodeFilter.indices(names: ["第1集"], query: "not-found"), [])
        XCTAssertEqual(NativeEpisodeFilter.indices(names: [], query: "第"), [])
    }

    func testDuplicateTitlesKeepDistinctPlaybackPositions() {
        XCTAssertEqual(NativeEpisodeFilter.indices(names: ["同名", "其他", "同名"], query: "同名"), [0, 2])
    }
}
