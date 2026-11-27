import XCTest
@testable import TVNext

final class NativeEpisodeRestartTests: XCTestCase {
    func testFirstPlayableSkipsUnavailable() {
        XCTAssertEqual(NativeEpisodeNavigation.firstPlayable([false, false, true, true]), 2)
        XCTAssertEqual(NativeEpisodeNavigation.firstPlayable([true, false]), 0)
    }

    func testNoPlayableEpisode() {
        XCTAssertNil(NativeEpisodeNavigation.firstPlayable([]))
        XCTAssertNil(NativeEpisodeNavigation.firstPlayable([false, false]))
    }

    func testReplayCurrentOnlyWhenValidAndPlayable() {
        XCTAssertEqual(NativeEpisodeNavigation.replayIndex(2, playable: [false, true, true]), 2)
        XCTAssertNil(NativeEpisodeNavigation.replayIndex(nil, playable: [true]))
        XCTAssertNil(NativeEpisodeNavigation.replayIndex(-1, playable: [true]))
        XCTAssertNil(NativeEpisodeNavigation.replayIndex(2, playable: [true]))
        XCTAssertNil(NativeEpisodeNavigation.replayIndex(0, playable: [false, true]))
    }
}
