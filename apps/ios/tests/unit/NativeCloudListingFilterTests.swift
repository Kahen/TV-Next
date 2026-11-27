import XCTest
@testable import TVNext

@MainActor
final class NativeCloudListingFilterTests: XCTestCase {
    private func entry(_ name: String, directory: Bool = false) -> NativeCloudPage.Entry {
        NativeCloudPage.Entry(name: name, directory: directory, size: 0)
    }

    func testFoldersFirstAndNaturalFileOrder() {
        let input = [entry("movie10.mp4"), entry("资料", directory: true),
                     entry("movie2.mp4"), entry("Archive", directory: true)]
        XCTAssertEqual(NativeCloudListingFilter.entries(input, query: "").map(\.name),
                       ["Archive", "资料", "movie2.mp4", "movie10.mp4"])
    }

    func testCaseInsensitiveSearchAndWhitespaceTrim() {
        let input = [entry("Movie.mp4"), entry("other.mkv"), entry("MOVIES", directory: true)]
        XCTAssertEqual(NativeCloudListingFilter.entries(input, query: " movie ").map(\.name),
                       ["MOVIES", "Movie.mp4"])
    }

    func testNoMatchesAndNoMutation() {
        let input = [entry("中文电影.mp4"), entry("series", directory: true)]
        XCTAssertTrue(NativeCloudListingFilter.entries(input, query: "absent").isEmpty)
        XCTAssertEqual(input.map(\.name), ["中文电影.mp4", "series"])
    }
}
