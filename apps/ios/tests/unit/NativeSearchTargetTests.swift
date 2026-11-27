import XCTest
@testable import TVNext

final class NativeSearchTargetTests: XCTestCase {
    func testAllRespectsSixteenProviderLimitAndDeduplicates() {
        let sources = [NativeSearchSource(key: "a", name: "First"),
                       NativeSearchSource(key: "a", name: "Duplicate")] +
            (0..<20).map { NativeSearchSource(key: "s\($0)", name: "Site") }
        XCTAssertEqual(NativeSearchTarget.resolve(sources, selectedKey: "").count, 16)
        XCTAssertEqual(NativeSearchTarget.resolve(sources, selectedKey: "").first?.name, "First")
    }

    func testSingleProviderBeyondDefaultLimitIsSearchable() {
        let sources = (0..<20).map { NativeSearchSource(key: "s\($0)", name: "Site") }
        XCTAssertEqual(NativeSearchTarget.resolve(sources, selectedKey: "s19").map(\.key), ["s19"])
    }

    func testStaleOrMalformedSelectionNeverExpandsToAll() {
        let sources = [NativeSearchSource(key: "ok", name: "OK"),
                       NativeSearchSource(key: "bad\nkey", name: "Invalid")]
        XCTAssertTrue(NativeSearchTarget.resolve(sources, selectedKey: "missing").isEmpty)
        XCTAssertTrue(NativeSearchTarget.resolve(sources, selectedKey: "bad\nkey").isEmpty)
        XCTAssertEqual(NativeSearchTarget.resolve(sources, selectedKey: "ok").map(\.key), ["ok"])
    }
}
