import XCTest
@testable import TVNext

final class CrossSiteRetryTests: XCTestCase {
    private struct Item {
        let id: String
    }

    func testFailureKeysAreDistinctFromDuplicateDisplayNames() async throws {
        let sources = [
            NativeSearchSource(key: "first", name: "Mirror"),
            NativeSearchSource(key: "second", name: "Mirror"),
            NativeSearchSource(key: "third", name: "Healthy")
        ]
        let result = try await NativeCrossSiteSearch.search(sources: sources, fetch: { source, _ in
            if source.key != "third" { throw NSError(domain: "secret", code: 1) }
            return NativeSearchPage(items: [Item(id: "ok")], hasMore: false)
        }, identity: { $0.id })
        XCTAssertEqual(result.failed, ["Mirror", "Mirror"])
        XCTAssertEqual(result.failedKeys, ["first", "second"])
        XCTAssertEqual(result.items.map(\.siteKey), ["third"])
    }

    func testFailedOnlySelectionUsesEligibleSitesAndDeduplicatesKeys() {
        // The caller has already filtered hidden/unsupported subscription sites.
        // A hidden duplicate may precede the eligible entry in the raw document,
        // but must never shadow the eligible provider during retry.
        let eligible = [
            NativeSearchSource(key: "a", name: "Healthy"),
            NativeSearchSource(key: "b", name: "Eligible B"),
            NativeSearchSource(key: "b", name: "Duplicate B")
        ]
        let selected = NativeCrossSiteSearch.failedOnlySources(
            eligible, failedKeys: ["b", "missing", "b"])
        XCTAssertEqual(selected.map(\.key), ["b"])
        XCTAssertEqual(selected.map(\.name), ["Eligible B"])
        XCTAssertTrue(NativeCrossSiteSearch.failedOnlySources(
            eligible, failedKeys: ["missing"]).isEmpty)
    }

    func testProviderDisplaySnapshotIgnoresRawHiddenDuplicateAndUnknownKeys() {
        // The caller has removed hidden/unsupported sites before building
        // this snapshot; the raw subscription's first key match is unsafe.
        let eligible = [
            NativeSearchSource(key: "a", name: "Mirror"),
            NativeSearchSource(key: "b", name: "Visible B"),
            NativeSearchSource(key: "b", name: "Duplicate B")
        ]
        let names = NativeCrossSiteSearch.selectedSourceNames(eligible)
        XCTAssertEqual(names, ["a": "Mirror", "b": "Visible B"])
        XCTAssertNil(names["not-searched"])
        let oversized = (0..<20).map {
            NativeSearchSource(key: String($0), name: "Site \($0)")
        }
        XCTAssertEqual(NativeCrossSiteSearch.selectedSourceNames(oversized).count, 16)
        XCTAssertNil(NativeCrossSiteSearch.selectedSourceNames(oversized)["16"])
    }

    func testExplicitEmptyStateDistinguishesNoMatchesFromProviderFailures() {
        XCTAssertEqual(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 0, selectedCount: 2),
                       "未找到匹配结果。")
        XCTAssertEqual(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 1, selectedCount: 2),
                       "尚无匹配结果，部分站点搜索失败，可重试。")
        XCTAssertEqual(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 2, selectedCount: 2),
                       "所有站点搜索失败，请重试失败站点。")
        XCTAssertNil(NativeCrossSiteSearch.emptyState(resultCount: 1, failedCount: 2, selectedCount: 2))
        XCTAssertNil(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 0, selectedCount: 0))
        XCTAssertNil(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: -1, selectedCount: 2))
    }

    func testRecoveredSiteReplacesPartialPageWithoutDiscardingOtherSites() {
        let original = [
            NativeSearchHit(siteKey: "a", item: Item(id: "a-old")),
            NativeSearchHit(siteKey: "b", item: Item(id: "b-partial")),
            NativeSearchHit(siteKey: "c", item: Item(id: "c-old"))
        ]
        let refreshed = [
            NativeSearchHit(siteKey: "b", item: Item(id: "b-new")),
            NativeSearchHit(siteKey: "b", item: Item(id: "b-new")),
            NativeSearchHit(siteKey: "c", item: Item(id: "c-ignored")),
            NativeSearchHit(siteKey: "foreign", item: Item(id: "injected"))
        ]
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: original, refreshed: refreshed,
            recoveredKeys: ["b", "foreign"], sourceOrder: ["a", "b", "c"],
            identity: { $0.id }
        )
        XCTAssertEqual(merged.map(\.siteKey), ["a", "b", "c"])
        XCTAssertEqual(merged.map { $0.item.id }, ["a-old", "b-new", "c-old"])
    }

    func testFailedRetryPreservesPreviousPartialHits() {
        let previous = [NativeSearchHit(siteKey: "failed", item: Item(id: "partial"))]
        let next = [NativeSearchHit(siteKey: "failed", item: Item(id: "new-partial"))]
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: previous, refreshed: next, recoveredKeys: [],
            sourceOrder: ["failed"], identity: { $0.id }
        )
        XCTAssertEqual(merged.map { $0.item.id }, ["partial"])
    }

    func testGlobalResultCapAndUnknownKeys() {
        let previous = [NativeSearchHit(siteKey: "a", item: Item(id: "stable"))]
        let refreshed = (0..<700).map { NativeSearchHit(siteKey: "b", item: Item(id: String($0))) }
            + [NativeSearchHit(siteKey: "outside", item: Item(id: "injected"))]
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: previous, refreshed: refreshed, recoveredKeys: ["b", "outside"],
            sourceOrder: ["a", "b"], identity: { $0.id }
        )
        XCTAssertEqual(merged.count, NativeCrossSiteSearch.maxResults)
        XCTAssertEqual(merged.first?.item.id, "stable")
        XCTAssertEqual(merged.last?.item.id, "598")
        XCTAssertFalse(merged.contains { $0.siteKey == "outside" })
    }
}
