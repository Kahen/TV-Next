import XCTest
@testable import TVNext

final class NativeEpisodeNavigationTests: XCTestCase {
    func testSkipsUnavailableEpisodesWithoutChangingOriginalIndex() {
        let playable = [true, false, true, false, true]
        XCTAssertEqual(NativeEpisodeNavigation.adjacent(to: 0, playable: playable, direction: 1), 2)
        XCTAssertEqual(NativeEpisodeNavigation.adjacent(to: 4, playable: playable, direction: -1), 2)
    }

    func testDoesNotWrapAtLineBoundaries() {
        let playable = [true, false, true]
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: 0, playable: playable, direction: -1))
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: 2, playable: playable, direction: 1))
    }

    func testRejectsMissingStaleOrInvalidNavigation() {
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: nil, playable: [true], direction: 1))
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: 3, playable: [true], direction: -1))
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: 0, playable: [true], direction: 0))
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: 0, playable: [], direction: 1))
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: 1, playable: [false, false], direction: 1))
    }
}
