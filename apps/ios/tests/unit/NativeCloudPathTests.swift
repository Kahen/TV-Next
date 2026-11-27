import XCTest
@testable import TVNext

final class NativeCloudPathTests: XCTestCase {
    func testValidNestedAndUnicodeNames() {
        XCTAssertEqual(NativeCloudPath.child(named: "电影 01.mkv", in: "/影视"), "/影视/电影 01.mkv")
        XCTAssertEqual(NativeCloudPath.child(named: "clip.mp4", in: "/"), "/clip.mp4")
        XCTAssertEqual(NativeCloudPath.parent(of: "/影视/电影 01.mkv"), "/影视")
        XCTAssertEqual(NativeCloudPath.parent(of: "/影视"), "/")
        XCTAssertEqual(NativeCloudPath.parent(of: "/"), "/")
    }

    func testRejectsTraversalAndSeparators() {
        for name in ["", ".", "..", "../private", "foo/bar", "foo\\bar", "a\nb", "a\u{2028}b"] {
            XCTAssertNil(NativeCloudPath.child(named: name, in: "/影视"), name)
        }
    }

    func testValidatesAndNormalizesServerDirectoryPaths() {
        XCTAssertEqual(NativeCloudPath.normalizedDirectory("/影视//剧集/"), "/影视/剧集")
        XCTAssertEqual(NativeCloudPath.normalizedDirectory("/"), "/")
        for path in ["relative", "/../outside", "/safe/./film", "/a\\b", "/a\u{202E}b", "/a\u{2029}b"] {
            XCTAssertNil(NativeCloudPath.normalizedDirectory(path), path)
            XCTAssertNil(NativeCloudPath.child(named: "film", in: path), path)
            XCTAssertEqual(NativeCloudPath.parent(of: path), "/")
        }
    }
}
