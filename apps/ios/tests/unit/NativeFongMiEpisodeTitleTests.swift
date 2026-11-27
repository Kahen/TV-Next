import XCTest
@testable import TVNext

final class NativeFongMiEpisodeTitleTests: XCTestCase {
    func testEpisodeTitleIncludedInPlaybackMetadata() {
        XCTAssertEqual(NativeFongMiEpisodeTitle.compose(series: "节目", episode: "第 2 集"), "节目 · 第 2 集")
    }

    func testDuplicateAndBlankEpisodeLabels() {
        XCTAssertEqual(NativeFongMiEpisodeTitle.compose(series: "节目", episode: "节目"), "节目")
        XCTAssertEqual(NativeFongMiEpisodeTitle.compose(series: "节目", episode: "   "), "节目")
    }

    func testRejectsURLAndInvisibleControlLabels() {
        XCTAssertEqual(NativeFongMiEpisodeTitle.compose(series: "节目", episode: "https://example.com/private"), "节目")
        XCTAssertEqual(NativeFongMiEpisodeTitle.compose(series: "节目", episode: "\u{202E}第\n3集"), "节目 · 第3集")
    }

    func testBoundsLongLabels() {
        XCTAssertLessThanOrEqual(NativeFongMiEpisodeTitle.compose(series: String(repeating: "a", count: 500), episode: "1").count, 124)
    }
}
