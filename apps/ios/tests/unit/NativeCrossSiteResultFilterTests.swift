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
}
