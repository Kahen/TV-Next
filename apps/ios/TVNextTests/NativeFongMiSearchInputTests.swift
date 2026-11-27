import XCTest
@testable import TVNext

final class NativeFongMiSearchInputTests: XCTestCase {
    func testAcceptsUnicodeAndPreservesInternalWhitespace() {
        XCTAssertEqual(NativeFongMiSearchInput.validated("  剧集  第2季  "), "剧集  第2季")
        XCTAssertEqual(NativeFongMiSearchInput.validated(String(repeating: "a", count: 256))?.count, 256)
    }

    func testRejectsEmptyOverlongAndInvisibleInputs() {
        XCTAssertNil(NativeFongMiSearchInput.validated(" \n "))
        XCTAssertNil(NativeFongMiSearchInput.validated(String(repeating: "a", count: 257)))
        XCTAssertNil(NativeFongMiSearchInput.validated("hello\u{0000}world"))
        XCTAssertNil(NativeFongMiSearchInput.validated("hello\u{202E}world"))
        XCTAssertNil(NativeFongMiSearchInput.validated("hello\u{2028}world"))
    }
}
