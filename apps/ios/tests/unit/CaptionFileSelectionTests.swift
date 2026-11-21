import Foundation
import XCTest
@testable import TVNext

final class CaptionFileSelectionTests: XCTestCase {
    private func files(_ names: String...) -> [URL] {
        names.map { URL(fileURLWithPath: "/selected").appendingPathComponent($0) }
    }

    func testRanksExactAndLanguageVariantsWithoutMatchingAdjacentEpisodes() throws {
        let urls = files("剧.S01E010.srt", "剧.s01e01.zh-Hans.ass", "剧.S01E01.MP4",
                         "剧.s01e01.SRT", "剧.S01E01.en.vtt")
        let selected = try LocalPlaybackFiles(urls)
        XCTAssertEqual(selected.media, urls[2])
        XCTAssertEqual(selected.captions, [urls[3], urls[4], urls[1]])
    }

    func testFallbackAndSingleFilePlayback() throws {
        let urls = files("Movie.mov", "中文.ssa", "English.vtt")
        XCTAssertEqual(try LocalPlaybackFiles(urls).captions, [urls[2], urls[1]])
        XCTAssertTrue(try LocalPlaybackFiles([urls[0]]).captions.isEmpty)
    }

    func testRejectsAmbiguousMediaAndUnsupportedSidecars() {
        for urls in [files("only.srt"), files("a.mp4", "b.mov"), files("a.mp4", "a.zip")] {
            XCTAssertThrowsError(try LocalPlaybackFiles(urls))
        }
    }
}
