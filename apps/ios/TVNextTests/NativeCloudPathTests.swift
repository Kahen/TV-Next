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
}
