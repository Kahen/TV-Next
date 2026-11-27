import XCTest
@testable import TVNext

final class NativeCrossSiteResultFilterTests: XCTestCase {
    private func hit(_ id: String, _ name: String, _ site: String) -> NativeSearchHit<NativeMediaItem> {
        NativeSearchHit(siteKey: site, item: NativeMediaItem(id: id, name: name, remarks: nil, folder: nil, action: nil))
    }

    func testEmptyQueryRetainsAllHitsAndOriginalOrder() {
        let hits = [hit("1", "电影二", "a"), hit("2", "电影十", "b")]
        let result = NativeCrossSiteResultFilter.apply(hits, query: "  ", names: [:])
        XCTAssertEqual(result.map { $0.item.id }, ["1", "2"])
    }

    func testMatchesUnicodeTitleOrProviderDisplayName() {
        let hits = [hit("1", "三体", "a"), hit("2", "Other", "b")]
        XCTAssertEqual(NativeCrossSiteResultFilter.apply(hits, query: " 三体 ", names: [:]).map { $0.item.id }, ["1"])
        let result = NativeCrossSiteResultFilter.apply(hits, query: "SOURCE B", names: ["b": "Source B"])
        XCTAssertEqual(result.map { $0.item.id }, ["2"])
        XCTAssertEqual(result.first?.siteKey, "b")
    }

    func testNoMatchAndNoCrossProviderIdentityMutation() {
        let hits = [hit("same", "Movie", "a"), hit("same", "Movie", "b")]
        XCTAssertTrue(NativeCrossSiteResultFilter.apply(hits, query: "absent", names: [:]).isEmpty)
        let result = NativeCrossSiteResultFilter.apply(hits, query: "movie", names: [:])
        XCTAssertEqual(result.map { $0.siteKey }, ["a", "b"])
        XCTAssertEqual(result.map { $0.item.id }, ["same", "same"])
    }

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
