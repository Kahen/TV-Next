import XCTest
@testable import TVNext

final class NativeCloudBreadcrumbsTests: XCTestCase {
    func testRootAndNestedUnicodeDirectory() {
        XCTAssertEqual(NativeCloudBreadcrumbs.make("/").map(\.path), ["/"])
        let crumbs = NativeCloudBreadcrumbs.make("/影视/Season 2")
        XCTAssertEqual(crumbs.map(\.title), ["根目录", "影视", "Season 2"])
        XCTAssertEqual(crumbs.map(\.path), ["/", "/影视", "/影视/Season 2"])
    }

    func testRejectsUntrustedPathsInsteadOfNavigating() {
        for value in ["relative/path", "//server/share", "/a/../b", "/a/./b",
                      "/a//b", "/a/", "/a\\b", "/a/\u{000A}b", "/a/\u{202E}b"] {
            XCTAssertEqual(NativeCloudBreadcrumbs.make(value).map(\.path), ["/"], value)
        }
    }

    func testKeepsExactCaseAndWhitespaceInValidSegments() {
        XCTAssertEqual(NativeCloudBreadcrumbs.make("/A b/剧集").last?.path, "/A b/剧集")
    }
}
