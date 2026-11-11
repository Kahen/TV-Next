import XCTest
@testable import TVNext

final class CrossSiteRetryTests: XCTestCase {
    private struct Item {
        let id: String
    }

    func testControlCharacterProviderKeysCannotEnterSearchOrRetry() async throws {
        let malformed = [
            NativeSearchSource(key: "bad\u{0000}key", name: "NUL"),
            NativeSearchSource(key: "bad\nkey", name: "Newline"),
            NativeSearchSource(key: "\u{001B}", name: "Escape")
        ]
        let allowed = NativeSearchSource(key: "valid", name: "Valid")
        XCTAssertEqual(NativeCrossSiteSearch.selectedSourceKeys(malformed + [allowed]), ["valid"])
        XCTAssertTrue(NativeCrossSiteSearch.failedOnlySources(
            malformed + [allowed], failedKeys: malformed.map(\.key),
            searchedKeys: malformed.map(\.key) + ["valid"]
        ).isEmpty)
        let result = try await NativeCrossSiteSearch.search(
            sources: malformed + [allowed],
            fetch: { source, _ in
                XCTAssertEqual(source.key, "valid")
                return NativeSearchPage(items: [Item(id: "ok")], hasMore: false)
            }, identity: { $0.id }
        )
        XCTAssertEqual(result.items.map(\.siteKey), ["valid"])
        XCTAssertTrue(result.failedKeys.isEmpty)
    }

    func testEmptyProviderKeysCannotConsumeSlotsOrBecomeRetryTargets() async throws {
        let malformed = [
            NativeSearchSource(key: "", name: "Empty"),
            NativeSearchSource(key: " \n ", name: "Whitespace")
        ]
        let valid = (0..<17).map { NativeSearchSource(key: "site-\($0)", name: "Site \($0)") }
        let selected = NativeCrossSiteSearch.selectedSources(malformed + valid)
        XCTAssertEqual(selected.count, NativeCrossSiteSearch.maxSites)
        XCTAssertEqual(selected.first?.key, "site-0")
        XCTAssertEqual(selected.last?.key, "site-15")
        XCTAssertEqual(NativeCrossSiteSearch.failedOnlySources(
            malformed + valid, failedKeys: ["", " \n ", "site-0"],
            searchedKeys: selected.map(\.key)
        ).map(\.key), ["site-0"])

        let result = try await NativeCrossSiteSearch.search(
            sources: malformed + [valid[0]],
            fetch: { source, _ in
                XCTAssertEqual(source.key, "site-0")
                return NativeSearchPage(items: [Item(id: "ok")], hasMore: false)
            }, identity: { $0.id }
        )
        XCTAssertEqual(result.items.map(\.siteKey), ["site-0"])
        XCTAssertEqual(result.failedKeys, [])
    }

    func testRecoveredRetryReconcilesWarningsByProviderKey() {
        let initial = NativeSearchWarningState(
            omittedSiteCount: 3, pageLimitKeys: ["a", "b"],
            clippedPageKeys: ["b", "c"], globalResultCapReached: true
        )
        let retry = NativeSearchWarningState(
            omittedSiteCount: 0, pageLimitKeys: ["b"],
            clippedPageKeys: [], globalResultCapReached: false
        )
        let merged = initial.replacingRecoveredProviders(with: retry, recoveredKeys: ["b"])
        XCTAssertEqual(merged.pageLimitKeys, ["a", "b"])
        XCTAssertEqual(merged.clippedPageKeys, ["c"])
        XCTAssertEqual(merged.omittedSiteCount, 3)
        XCTAssertTrue(merged.globalResultCapReached)
        XCTAssertEqual(merged.messages.count, 4)
        XCTAssertEqual(merged.messages[2], "1 个站点单页超过 40 条，仅保留每页前 40 条。")
        // A failed-again provider retains its old partial hits and warnings.
        XCTAssertEqual(initial.replacingRecoveredProviders(with: .empty, recoveredKeys: []).messages,
                       initial.messages)
        let clear = initial.replacingRecoveredProviders(with: .empty, recoveredKeys: ["b"])
        XCTAssertEqual(clear.clippedPageKeys, ["c"])
        XCTAssertEqual(clear.pageLimitKeys, ["a"])
    }

    func testDistinctClippedProvidersAreCountedByKey() {
        let original = NativeSearchWarningState(
            omittedSiteCount: 0, pageLimitKeys: [],
            clippedPageKeys: ["a"], globalResultCapReached: false
        )
        let retried = NativeSearchWarningState(
            omittedSiteCount: 0, pageLimitKeys: [],
            clippedPageKeys: ["b"], globalResultCapReached: false
        )
        let combined = original.replacingRecoveredProviders(with: retried, recoveredKeys: ["b"])
        XCTAssertEqual(combined.clippedPageKeys, ["a", "b"])
        XCTAssertEqual(combined.messages, ["2 个站点单页超过 40 条，仅保留每页前 40 条。"])
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
            eligible, failedKeys: ["b", "missing", "b"], searchedKeys: ["a", "b"])
        XCTAssertEqual(selected.map(\.key), ["b"])
        XCTAssertEqual(selected.map(\.name), ["Eligible B"])
        XCTAssertTrue(NativeCrossSiteSearch.failedOnlySources(
            eligible, failedKeys: ["missing"], searchedKeys: ["a", "b"]).isEmpty)
    }

    func testRetryCannotExpandBeyondOriginalSixteenUniqueSites() {
        let eligible = (0..<18).map { NativeSearchSource(key: String($0), name: "Site \($0)") }
        let initial = NativeCrossSiteSearch.selectedSourceKeys(eligible)
        XCTAssertEqual(initial.count, 16)
        let retry = NativeCrossSiteSearch.failedOnlySources(
            eligible, failedKeys: ["16", "15", "0", "unknown"], searchedKeys: initial)
        XCTAssertEqual(retry.map(\.key), ["0", "15"])
        XCTAssertEqual(NativeCrossSiteSearch.failedOnlySources(
            eligible, failedKeys: ["0", "1", "16"], searchedKeys: ["1"]).map(\.key), ["1"])

        // A new first site displaces the former last selected site. Neither
        // that displaced site nor the new one was eligible for this retry.
        let changed = [NativeSearchSource(key: "new", name: "New")] + eligible
        XCTAssertTrue(NativeCrossSiteSearch.failedOnlySources(
            changed, failedKeys: ["15", "new", "16"], searchedKeys: initial).isEmpty)

        // Duplicate keys before the boundary count only once; preserve the
        // first eligible provider, never its later display-name duplicate.
        let duplicated = [eligible[0], NativeSearchSource(key: "0", name: "Spoof")] + eligible.dropFirst()
        let selected = NativeCrossSiteSearch.failedOnlySources(
            Array(duplicated), failedKeys: ["0", "15", "16"],
            searchedKeys: NativeCrossSiteSearch.selectedSourceKeys(Array(duplicated)))
        XCTAssertEqual(selected.map(\.key), ["0", "15"])
        XCTAssertEqual(selected.first?.name, "Site 0")
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
        XCTAssertNil(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 3, selectedCount: 2))
        XCTAssertEqual(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 2, selectedCount: 2), "所有站点搜索失败，请重试失败站点。")
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
        XCTAssertEqual(merged.count, NativeCrossSiteSearch.maxPages * NativeCrossSiteSearch.maxItemsPerPage + 1)
        XCTAssertEqual(merged.first?.item.id, "stable")
        XCTAssertEqual(merged.last?.item.id, "79")
        XCTAssertFalse(merged.contains { $0.siteKey == "outside" })
    }
    func testRetryReconciliationBoundsEveryProviderAndKeepsOriginalOrder() {
        let previous = (0..<200).map { NativeSearchHit(siteKey: "stable", item: Item(id: "s\($0)")) }
        let refreshed = (0..<200).map { NativeSearchHit(siteKey: "recovered", item: Item(id: "r\($0)")) }
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: previous, refreshed: refreshed, recoveredKeys: ["recovered"],
            sourceOrder: ["stable", "recovered"], identity: { $0.id }
        )
        XCTAssertEqual(merged.count, 160)
        XCTAssertEqual(merged[0].item.id, "s0")
        XCTAssertEqual(merged[79].item.id, "s79")
        XCTAssertEqual(merged[80].item.id, "r0")
        XCTAssertEqual(merged[159].item.id, "r79")
    }

    func testRetryReconciliationRejectsUnselectedOverflowAndFailedRefresh() {
        let previous = [NativeSearchHit(siteKey: "failed", item: Item(id: "old"))]
        let refreshed = (0..<1000).map { NativeSearchHit(siteKey: "failed", item: Item(id: "new\($0)")) }
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: previous, refreshed: refreshed, recoveredKeys: [],
            sourceOrder: ["failed"], identity: { $0.id }
        )
        XCTAssertEqual(merged.map { $0.item.id }, ["old"])
    }

    func testTerminalOversizedPageWarnsWithoutClaimingAdditionalPages() async throws {
        let result = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "a", name: "Provider")],
            fetch: { _, _ in
                NativeSearchPage(items: (0..<41).map { Item(id: String($0)) }, hasMore: false)
            }, identity: { $0.id }
        )
        XCTAssertEqual(result.items.count, 40)
        XCTAssertEqual(result.items.last?.item.id, "39")
        XCTAssertEqual(result.warnings, ["1 个站点单页超过 40 条，仅保留每页前 40 条。"])
        XCTAssertTrue(result.failedKeys.isEmpty)
    }

    func testExactPageBoundaryHasNoFalseTruncationWarning() async throws {
        let result = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "a", name: "Provider")],
            fetch: { _, _ in
                NativeSearchPage(items: (0..<40).map { Item(id: String($0)) }, hasMore: false)
            }, identity: { $0.id }
        )
        XCTAssertEqual(result.items.count, 40)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testMorePagesAndOversizedResponseHaveDistinctWarnings() async throws {
        let result = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "a", name: "Provider")],
            fetch: { _, page in
                NativeSearchPage(items: (0..<41).map { Item(id: "\(page)-\($0)") }, hasMore: true)
            }, identity: { $0.id }
        )
        XCTAssertEqual(result.items.count, 80)
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertTrue(result.warnings.contains { $0.contains("仍有更多结果") })
        XCTAssertTrue(result.warnings.contains { $0.contains("单页超过 40") })
    }

    func testPartialFailurePreservesClippedPageWarning() async throws {
        let result = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "a", name: "Provider")],
            fetch: { _, page in
                if page == 2 { throw NSError(domain: "private", code: 1) }
                return NativeSearchPage(items: (0..<41).map { Item(id: String($0)) }, hasMore: true)
            }, identity: { $0.id }
        )
        XCTAssertEqual(result.items.count, 40)
        XCTAssertEqual(result.failedKeys, ["a"])
        XCTAssertEqual(result.warnings, ["1 个站点单页超过 40 条，仅保留每页前 40 条。"])
        XCTAssertFalse(result.warnings.joined().contains("private"))
    }

    func testRetryCapCountsDistinctValidHitsRatherThanDuplicateEntries() {
        let previous = [NativeSearchHit(siteKey: "a", item: Item(id: "old"))]
        let duplicatePrefix = (0..<100).map { _ in NativeSearchHit(siteKey: "b", item: Item(id: "same")) }
        let uniqueTail = (0..<90).map { NativeSearchHit(siteKey: "b", item: Item(id: "tail-\($0)")) }
        let refreshed = duplicatePrefix + [NativeSearchHit(siteKey: "b", item: Item(id: ""))] + uniqueTail
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: previous, refreshed: refreshed, recoveredKeys: ["b"],
            sourceOrder: ["a", "b"], identity: { $0.id }
        )
        XCTAssertEqual(merged.count, 81)
        XCTAssertEqual(merged.first?.item.id, "old")
        XCTAssertEqual(merged[1].item.id, "same")
        XCTAssertEqual(merged.last?.item.id, "tail-78")
        XCTAssertFalse(merged.contains { $0.item.id == "tail-79" })
    }

    func testRetryCannotInjectForeignOrFailedAgainProviderHits() {
        let previous = [NativeSearchHit(siteKey: "a", item: Item(id: "retained"))]
        let refreshed = [
            NativeSearchHit(siteKey: "a", item: Item(id: "replace-attempt")),
            NativeSearchHit(siteKey: "foreign", item: Item(id: "foreign")),
            NativeSearchHit(siteKey: "b", item: Item(id: "valid"))
        ]
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: previous, refreshed: refreshed, recoveredKeys: ["b", "foreign"],
            sourceOrder: ["a", "b"], identity: { $0.id }
        )
        XCTAssertEqual(merged.map { $0.item.id }, ["retained", "valid"])
    }

    func testMalformedOriginalSearchKeysDoNotConsumeRetrySlots() {
        let eligible = (0..<17).map { NativeSearchSource(key: "site-\($0)", name: "Site \($0)") }
        let snapshot = ["", "  ", "site-0", "site-0"] + (1..<16).map { "site-\($0)" }
        let retry = NativeCrossSiteSearch.failedOnlySources(
            eligible, failedKeys: ["", "  ", "site-15", "site-16"], searchedKeys: snapshot
        )
        XCTAssertEqual(retry.map(\.key), ["site-15"])
    }

    func testMalformedAndDuplicateOrderDoesNotEvictLastValidProviderOnMerge() {
        let original = [
            NativeSearchHit(siteKey: "site-0", item: Item(id: "old")),
            NativeSearchHit(siteKey: "site-15", item: Item(id: "last"))
        ]
        let injected = [NativeSearchHit(siteKey: "site-16", item: Item(id: "foreign"))]
        let order = ["", "  ", "site-0", "site-0"] + (1..<16).map { "site-\($0)" }
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: original, refreshed: injected, recoveredKeys: ["site-16"],
            sourceOrder: order, identity: { $0.id }
        )
        XCTAssertEqual(merged.map(\.siteKey), ["site-0", "site-15"])
        XCTAssertEqual(merged.map { $0.item.id }, ["old", "last"])
    }

}
