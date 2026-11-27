import XCTest
@testable import TVNext

final class NativeEpisodeAutoNextTests: XCTestCase {
    func testAdvancesPastUnavailableEpisodes() {
        XCTAssertEqual(NativeEpisodeNavigation.adjacent(to: 0, playable: [true, false, true], direction: 1), 2)
    }

    func testDoesNotWrapAtLastEpisode() {
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: 2, playable: [true, false, true], direction: 1))
    }

    func testRejectsUnknownOrInvalidCurrentEpisode() {
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: nil, playable: [true], direction: 1))
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: -1, playable: [true], direction: 1))
        XCTAssertNil(NativeEpisodeNavigation.adjacent(to: 0, playable: [], direction: 1))
    }
}
