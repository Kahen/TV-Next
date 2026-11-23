import XCTest
@testable import TVNext

final class NativeCrossSiteResultFilterTests: XCTestCase {
    func testSelectionReconciliation() {
        XCTAssertEqual(NativeCrossSiteResultFilter.reconciledSelection("site-a", searchedKeys: ["site-a", "site-b"]), "site-a")
        XCTAssertEqual(NativeCrossSiteResultFilter.reconciledSelection("removed", searchedKeys: ["site-a"]), "")
        XCTAssertEqual(NativeCrossSiteResultFilter.reconciledSelection("", searchedKeys: []), "")
    }

    func testFilteringPreservesOriginalHitsAndOrder() {
        let hits = [
            NativeSearchHit(siteKey: "a", item: "first"),
            NativeSearchHit(siteKey: "b", item: "second"),
            NativeSearchHit(siteKey: "a", item: "third")
        ]
        XCTAssertEqual(NativeCrossSiteResultFilter.visible(hits, selectedKey: "a", searchedKeys: ["a", "b"]).map(\.item), ["first", "third"])
        XCTAssertEqual(NativeCrossSiteResultFilter.visible(hits, selectedKey: "", searchedKeys: ["a", "b"]).map(\.item), ["first", "second", "third"])
        XCTAssertEqual(NativeCrossSiteResultFilter.visible(hits, selectedKey: "unknown", searchedKeys: ["a", "b"]).count, 3)
        XCTAssertEqual(hits.count, 3)
    }
}
