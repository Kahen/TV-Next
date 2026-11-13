import Foundation

private actor RequestCounter {
    var active = 0
    var peak = 0
    var calls: [String] = []
    func begin(_ value: String) { active += 1; peak = max(peak, active); calls.append(value) }
    func end() { active -= 1 }
    func snapshot() -> (Int, [String]) { (peak, calls) }
}

@main struct CrossSiteSearchSmoke {
    struct Item { let id: String }
    static func main() async throws {
        let malformedResultIds = ["bad\u{0000}id", "bad\u{200B}id", "bad\u{202E}id"]
        let safeResultIds = ["合法", "id with spaces", "café"]
        let identityBoundary = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "owned", name: "Owned")],
            fetch: { _, _ in
                NativeSearchPage(items: (malformedResultIds + safeResultIds).map { Item(id: $0) }, hasMore: false)
            }, identity: { $0.id }
        )
        precondition(identityBoundary.items.map(\.item.id) == safeResultIds)
        let identityRetry = NativeCrossSiteSearch.mergeRetry(
            previous: [NativeSearchHit(siteKey: "owned", item: Item(id: "old"))],
            refreshed: (malformedResultIds + safeResultIds).map { NativeSearchHit(siteKey: "owned", item: Item(id: $0)) },
            recoveredKeys: ["owned"], sourceOrder: ["owned"], identity: { $0.id }
        )
        precondition(identityRetry.map(\.item.id) == safeResultIds)
        let separators = [
            NativeSearchSource(key: "bad\u{2028}key", name: "Line"),
            NativeSearchSource(key: "bad\u{2029}key", name: "Paragraph")
        ]
        precondition(NativeCrossSiteSearch.selectedSourceKeys(
            separators + [NativeSearchSource(key: "合法", name: "Allowed")]
        ) == ["合法"])
        let separatorResult = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "合法", name: "Allowed")],
            fetch: { _, _ in
                NativeSearchPage(items: [
                    Item(id: "bad\u{2028}id"), Item(id: "bad\u{2029}id"),
                    Item(id: "café")
                ], hasMore: false)
            }, identity: { $0.id }
        )
        precondition(separatorResult.items.map(\.item.id) == ["café"])
        let separatorRetry = NativeCrossSiteSearch.mergeRetry(
            previous: [], refreshed: [
                NativeSearchHit(siteKey: "合法", item: Item(id: "bad\u{2029}id")),
                NativeSearchHit(siteKey: "合法", item: Item(id: "café"))
            ], recoveredKeys: ["合法"], sourceOrder: ["合法"], identity: { $0.id }
        )
        precondition(separatorRetry.map(\.item.id) == ["café"])
        let blankIdentity = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "owned", name: "Owned")],
            fetch: { _, _ in
                NativeSearchPage(items: [Item(id: " "), Item(id: "\n\t"), Item(id: "valid"), Item(id: "合法")], hasMore: false)
            }, identity: { $0.id }
        )
        precondition(blankIdentity.items.map(\.item.id) == ["valid", "合法"])
        let filteredRetry = NativeCrossSiteSearch.mergeRetry(
            previous: [NativeSearchHit(siteKey: "owned", item: Item(id: "old"))],
            refreshed: [
                NativeSearchHit(siteKey: "owned", item: Item(id: "  ")),
                NativeSearchHit(siteKey: "owned", item: Item(id: "valid"))
            ],
            recoveredKeys: ["owned"], sourceOrder: ["owned"], identity: { $0.id }
        )
        precondition(filteredRetry.map(\.item.id) == ["valid"])
        let invisible = [
            NativeSearchSource(key: "site\u{200B}hidden", name: "Zero width"),
            NativeSearchSource(key: "site\u{202E}spoof", name: "Bidi override"),
            NativeSearchSource(key: "\u{2060}", name: "Word joiner")
        ]
        let unicodeSafe = NativeSearchSource(key: "站点-合法", name: "Unicode")
        precondition(NativeCrossSiteSearch.selectedSourceKeys(invisible + [unicodeSafe]) == ["站点-合法"])
        precondition(NativeCrossSiteSearch.failedOnlySources(
            invisible + [unicodeSafe], failedKeys: invisible.map(\.key),
            searchedKeys: invisible.map(\.key) + ["站点-合法"]
        ).isEmpty)
        let invisibleResult = try await NativeCrossSiteSearch.search(
            sources: invisible + [unicodeSafe],
            fetch: { source, _ in
                precondition(source.key == "站点-合法")
                return NativeSearchPage(items: [Item(id: "ok")], hasMore: false)
            }, identity: { $0.id }
        )
        precondition(invisibleResult.items.map(\.siteKey) == ["站点-合法"])
        let malformed = [
            NativeSearchSource(key: "bad\u{0000}key", name: "NUL"),
            NativeSearchSource(key: "bad\nkey", name: "Newline"),
            NativeSearchSource(key: "\u{001B}", name: "Escape")
        ]
        let safe = NativeSearchSource(key: "safe", name: "Safe")
        precondition(NativeCrossSiteSearch.selectedSourceKeys(malformed + [safe]) == ["safe"])
        precondition(NativeCrossSiteSearch.failedOnlySources(
            malformed + [safe], failedKeys: malformed.map(\.key),
            searchedKeys: malformed.map(\.key) + ["safe"]
        ).isEmpty)
        let sanitized = try await NativeCrossSiteSearch.search(
            sources: malformed + [safe],
            fetch: { source, _ in
                precondition(source.key == "safe")
                return NativeSearchPage(items: [Item(id: "ok")], hasMore: false)
            }, identity: { $0.id }
        )
        precondition(sanitized.items.map(\.siteKey) == ["safe"])
        let sources = (0..<6).map { NativeSearchSource(key: String($0), name: "Source \($0)") }
        let counter = RequestCounter()
        let result = try await NativeCrossSiteSearch.search(sources: sources, fetch: { source, page in
            await counter.begin("\(source.key):\(page)")
            try await Task.sleep(for: .milliseconds(source.key == "0" ? 10 : 3))
            await counter.end()
            if source.key == "0" && page == 1 { return NativeSearchPage(items: [Item(id:"shared")], hasMore:true) }
            if source.key == "0" { return NativeSearchPage(items:[Item(id:"shared"),Item(id:"next")],hasMore:false) }
            if source.key == "1" { throw NSError(domain:"secret token",code:1) }
            return NativeSearchPage(items:[Item(id:"shared")],hasMore:false)
        }, identity: { $0.id })
        precondition(result.items.map { "\($0.siteKey):\($0.item.id)" } == ["0:shared","0:next","2:shared","3:shared","4:shared","5:shared"])
        precondition(result.failed == ["Source 1"])
        precondition(!String(describing:result.failed).contains("secret"))
        let (peak, calls) = await counter.snapshot()
        precondition(peak > 1 && peak <= 4, "Concurrent site count outside 2...4")
        precondition(calls.contains("0:2"))

        let androidCounter = RequestCounter()
        let android = try await NativeCrossSiteSearch.search(sources:sources,concurrency:2,fetch:{ source,_ in
            await androidCounter.begin(source.key)
            try await Task.sleep(for:.milliseconds(3))
            await androidCounter.end()
            return NativeSearchPage(items:[Item(id:"own")],hasMore:false)
        },identity:{$0.id})
        let (androidPeak,_) = await androidCounter.snapshot()
        precondition(androidPeak == 2 && android.items.count == 6)

        let bounded = try await NativeCrossSiteSearch.search(sources:(0..<20).map { NativeSearchSource(key:String($0),name:String($0)) }, fetch: { source, page in
            NativeSearchPage(items:[Item(id:"\(source.key)-\(page)")],hasMore:true)
        }, identity: { $0.id })
        precondition(bounded.items.count == 32)
        precondition(bounded.warnings.count == 2)
        precondition(!bounded.items.contains(where:{$0.siteKey == "16"}))
        let duplicates = try await NativeCrossSiteSearch.search(sources:[sources[0],sources[0]],fetch:{ _,_ in
            NativeSearchPage(items:[Item(id:""),Item(id:"x"),Item(id:"x")],hasMore:false)
        },identity:{$0.id})
        precondition(duplicates.items.count == 1)
        let capped = try await NativeCrossSiteSearch.search(sources:(0..<16).map { NativeSearchSource(key:String($0),name:String($0)) },fetch:{ source,page in
            NativeSearchPage(items:(0..<50).map { Item(id:"\(source.key)-\(page)-\($0)") },hasMore:true)
        },identity:{$0.id})
        precondition(capped.items.count == 600)
        precondition(capped.warnings.contains(where:{$0.contains("600")}))
        let task = Task { try await NativeCrossSiteSearch.search(sources:sources,fetch:{ _,_ in
            try await Task.sleep(for:.seconds(3))
            return NativeSearchPage(items:[Item(id:"stale")],hasMore:false)
        },identity:{$0.id}) }
        task.cancel()
        do { _ = try await task.value; fatalError("Cancellation was ignored") } catch is CancellationError {}
        // Empty successful results, partial failure and total failure must
        // not collapse into the same ambiguous blank UI.
        precondition(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 0, selectedCount: 2) == "未找到匹配结果。")
        precondition(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 1, selectedCount: 2) == "尚无匹配结果，部分站点搜索失败，可重试。")
        precondition(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 2, selectedCount: 2) == "所有站点搜索失败，请重试失败站点。")
        precondition(NativeCrossSiteSearch.emptyState(resultCount: 1, failedCount: 2, selectedCount: 2) == nil)
        precondition(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 0, selectedCount: 0) == nil)
        precondition(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: -1, selectedCount: 2) == nil)
        precondition(NativeCrossSiteSearch.emptyState(resultCount: 0, failedCount: 3, selectedCount: 2) == nil)
        // Opening a search hit from B after browsing A must not leak A's
        // category filters into subsequent B requests. Same-site detail keeps them.
        var scope = NativeSiteBrowsingContext<String>(
            siteKey: "A", category: "shared", mode: "category",
            filterCatalog: ["shared": ["A-only"]],
            filters: ["quality": "A"], appliedFilters: ["quality": "A"]
        )
        precondition(!scope.switchToDetailSite("A"))
        precondition(scope.category == "shared" && scope.filters["quality"] == "A")
        precondition(scope.switchToDetailSite("B"))
        precondition(scope.siteKey == "B" && scope.category == nil && scope.mode == "home")
        precondition(scope.filterCatalog.isEmpty && scope.filters.isEmpty && scope.appliedFilters.isEmpty)
        precondition(!scope.switchToDetailSite("B"))
        // Duplicate subscription keys must not shift the 16-site boundary:
        // search and retry ordering must select the same unique providers.
        let repeatedSources = [
            NativeSearchSource(key: "a", name: "A"),
            NativeSearchSource(key: "a", name: "Duplicate A"),
            NativeSearchSource(key: "b", name: "B")
        ]
        precondition(NativeCrossSiteSearch.selectedSourceKeys(repeatedSources) == ["a", "b"])
        // The UI must render provenance from the eligible searched sites,
        // never the first raw-subscription entry with a matching key.
        let eligibleNames = [
            NativeSearchSource(key: "a", name: "Visible A"),
            NativeSearchSource(key: "b", name: "Visible B"),
            NativeSearchSource(key: "b", name: "Duplicate Eligible B")
        ]
        let names = NativeCrossSiteSearch.selectedSourceNames(eligibleNames)
        precondition(names == ["a": "Visible A", "b": "Visible B"])
        precondition(names["unknown"] == nil)
        let limitedNames = NativeCrossSiteSearch.selectedSourceNames(
            (0..<20).map { NativeSearchSource(key: String($0), name: "Visible \($0)") }
        )
        precondition(limitedNames.count == 16 && limitedNames["15"] == "Visible 15")
        precondition(limitedNames["16"] == nil)
        precondition(NativeCrossSiteSearch.selectedSources(repeatedSources).map(\.name) == ["A", "B"])
        // The UI filters hidden/unsupported subscription entries *before*
        // resolving failed keys. A hidden first occurrence of "b" must not
        // shadow a later eligible "b"; duplicate eligible keys are requested once.
        let eligibleForRetry = [
            NativeSearchSource(key: "a", name: "Visible A"),
            NativeSearchSource(key: "b", name: "Visible B"),
            NativeSearchSource(key: "b", name: "Duplicate B")
        ]
        let failedOnly = NativeCrossSiteSearch.failedOnlySources(
            eligibleForRetry, failedKeys: ["b", "missing", "b"], searchedKeys: ["a", "b"])
        precondition(failedOnly.map(\.key) == ["b"])
        precondition(failedOnly.map(\.name) == ["Visible B"])
        precondition(NativeCrossSiteSearch.failedOnlySources(
            eligibleForRetry, failedKeys: ["unknown"], searchedKeys: ["a", "b"]).isEmpty)

        // The original search selected only the first 16 distinct sites.
        // A foreign/stale failure key, including site 17, cannot widen retry.
        let oversizedEligible = (0..<18).map {
            NativeSearchSource(key: String($0), name: "Site \($0)")
        }
        let boundedRetry = NativeCrossSiteSearch.failedOnlySources(
            oversizedEligible, failedKeys: ["16", "15", "0", "unknown"],
            searchedKeys: NativeCrossSiteSearch.selectedSourceKeys(oversizedEligible))
        precondition(boundedRetry.map(\.key) == ["0", "15"])
        precondition(NativeCrossSiteSearch.failedOnlySources(
            oversizedEligible, failedKeys: ["0", "1", "16"],
            searchedKeys: ["1"]).map(\.key) == ["1"])
        // Inserting a new eligible site must not accidentally select a
        // previously unsearched site or resurrect a displaced provider.
        let changedEligible = [NativeSearchSource(key: "new", name: "New")] + oversizedEligible
        precondition(NativeCrossSiteSearch.failedOnlySources(
            changedEligible, failedKeys: ["15", "new", "16"],
            searchedKeys: NativeCrossSiteSearch.selectedSourceKeys(oversizedEligible)).isEmpty)
        let boundaryCounter = RequestCounter()
        let boundedResult = try await NativeCrossSiteSearch.search(sources: boundedRetry, fetch: { source, _ in
            await boundaryCounter.begin(source.key)
            await boundaryCounter.end()
            return NativeSearchPage(items: [Item(id: source.key)], hasMore: false)
        }, identity: { $0.id })
        let (_, retriedKeys) = await boundaryCounter.snapshot()
        precondition(Set(retriedKeys) == Set(["0", "15"]))
        precondition(boundedResult.items.map(\.siteKey) == ["0", "15"])

        // A retry is routed by provider key, not display name. Failed page-2
        // providers retain their partial results until a successful retry.
        let sameNames = [
            NativeSearchSource(key: "a", name: "Mirror"),
            NativeSearchSource(key: "b", name: "Mirror"),
            NativeSearchSource(key: "c", name: "Other")
        ]
        let first = try await NativeCrossSiteSearch.search(sources: sameNames, fetch: { source, page in
            if source.key == "b" { throw NSError(domain: "private token", code: 1) }
            if source.key == "c" && page == 2 { throw NSError(domain: "private token", code: 2) }
            return NativeSearchPage(items: [Item(id: source.key + "-old")],
                                    hasMore: source.key == "c")
        }, identity: { $0.id })
        precondition(first.failed == ["Mirror", "Other"])
        precondition(first.failedKeys == ["b", "c"])
        precondition(first.items.map { $0.item.id } == ["a-old", "c-old"])

        let originalKeyword = "original"
        let editedDraft = "different"
        let retrySources = first.failedKeys.compactMap { key in sameNames.first { $0.key == key } }
        let retryCounter = RequestCounter()
        let retry = try await NativeCrossSiteSearch.search(sources: retrySources, fetch: { source, _ in
            await retryCounter.begin(source.key + ":" + originalKeyword)
            await retryCounter.end()
            if source.key == "c" { throw NSError(domain: "private token", code: 3) }
            return NativeSearchPage(items: [Item(id: "b-new"), Item(id: "b-new")], hasMore: false)
        }, identity: { $0.id })
        let (_, retriedCalls) = await retryCounter.snapshot()
        precondition(editedDraft != originalKeyword)
        precondition(Set(retriedCalls) == Set(["b:original", "c:original"]))
        precondition(retry.failedKeys == ["c"])
        let recovered = Set(retrySources.map(\.key)).subtracting(retry.failedKeys)
        let merged = NativeCrossSiteSearch.mergeRetry(
            previous: first.items, refreshed: retry.items,
            recoveredKeys: recovered, sourceOrder: sameNames.map(\.key), identity: { $0.id }
        )
        precondition(merged.map { $0.item.id } == ["a-old", "b-new", "c-old"])
        // Unknown provider injection and duplicate source order are ignored.
        let injected = NativeCrossSiteSearch.mergeRetry(
            previous: merged,
            refreshed: [NativeSearchHit(siteKey: "unrequested", item: Item(id: "bad"))],
            recoveredKeys: ["unrequested"], sourceOrder: ["a", "b", "b", "c"],
            identity: { $0.id }
        )
        precondition(injected.map { $0.item.id } == merged.map { $0.item.id })
        // Retry reconciliation applies the 80-result per-provider cap before the global cap.
        let many = (0..<700).map { NativeSearchHit(siteKey: "b", item: Item(id: String($0))) }
        let cappedRetry = NativeCrossSiteSearch.mergeRetry(
            previous: first.items, refreshed: many, recoveredKeys: ["b"],
            sourceOrder: ["a", "b", "c"], identity: { $0.id }
        )
        precondition(cappedRetry.count == 82)
        precondition(cappedRetry.first?.item.id == "a-old")
        precondition(cappedRetry[80].item.id == "79")
        precondition(cappedRetry.last?.item.id == "c-old")

        // Duplicate-heavy retry pages must not exhaust the 80 distinct-hit
        // allowance before later valid results are considered.
        let duplicateHeavy = (0..<100).map { _ in NativeSearchHit(siteKey: "b", item: Item(id: "same")) }
            + (0..<90).map { NativeSearchHit(siteKey: "b", item: Item(id: "tail-\($0)")) }
        let uniqueRetry = NativeCrossSiteSearch.mergeRetry(
            previous: first.items, refreshed: duplicateHeavy, recoveredKeys: ["b"],
            sourceOrder: ["a", "b", "c"], identity: { $0.id }
        )
        precondition(uniqueRetry.count == 82)
        precondition(uniqueRetry[1].item.id == "same")
        precondition(uniqueRetry[80].item.id == "tail-78")
        precondition(uniqueRetry.last?.item.id == "c-old")

        // A provider returning 41 entries with hasMore=false still silently
        // loses its 41st entry unless the per-page clip is reported.
        let clippedTerminal = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "oversized", name: "Oversized")],
            fetch: { _, _ in
                NativeSearchPage(items: (0..<41).map { Item(id: String($0)) }, hasMore: false)
            }, identity: { $0.id }
        )
        precondition(clippedTerminal.items.count == 40)
        precondition(clippedTerminal.items.last?.item.id == "39")
        precondition(clippedTerminal.failedKeys.isEmpty)
        precondition(clippedTerminal.warnings == ["1 个站点单页超过 40 条，仅保留每页前 40 条。"])

        let exactBoundary = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "exact", name: "Exact")],
            fetch: { _, _ in
                NativeSearchPage(items: (0..<40).map { Item(id: String($0)) }, hasMore: false)
            }, identity: { $0.id }
        )
        precondition(exactBoundary.items.count == 40 && exactBoundary.warnings.isEmpty)

        let clippedAndMore = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "both", name: "Both")],
            fetch: { _, page in
                NativeSearchPage(items: (0..<41).map { Item(id: "\(page)-\($0)") }, hasMore: true)
            }, identity: { $0.id }
        )
        precondition(clippedAndMore.items.count == 80)
        precondition(clippedAndMore.warnings.count == 2)
        precondition(clippedAndMore.warnings.contains { $0.contains("仍有更多结果") })
        precondition(clippedAndMore.warnings.contains { $0.contains("单页超过 40") })

        let clippedThenFailed = try await NativeCrossSiteSearch.search(
            sources: [NativeSearchSource(key: "partial", name: "Partial")],
            fetch: { _, page in
                if page == 2 { throw NSError(domain: "private", code: 1) }
                return NativeSearchPage(items: (0..<41).map { Item(id: String($0)) }, hasMore: true)
            }, identity: { $0.id }
        )
        precondition(clippedThenFailed.items.count == 40)
        precondition(clippedThenFailed.failedKeys == ["partial"])
        precondition(clippedThenFailed.warnings == ["1 个站点单页超过 40 条，仅保留每页前 40 条。"])

        let initialWarnings = NativeSearchWarningState(
            omittedSiteCount: 2, pageLimitKeys: ["a", "b"],
            clippedPageKeys: ["b"], globalResultCapReached: true
        )
        let recoveredB = NativeSearchWarningState.empty
        let unchanged = initialWarnings.replacingRecoveredProviders(with: recoveredB, recoveredKeys: [])
        precondition(unchanged.messages == initialWarnings.messages)
        let reconciled = initialWarnings.replacingRecoveredProviders(with: recoveredB, recoveredKeys: ["b"])
        precondition(reconciled.pageLimitKeys == ["a"] && reconciled.clippedPageKeys.isEmpty)
        precondition(reconciled.omittedSiteCount == 2 && reconciled.globalResultCapReached)
        precondition(reconciled.messages.count == 3)
        let twoClipped = NativeSearchWarningState(
            omittedSiteCount: 0, pageLimitKeys: [],
            clippedPageKeys: ["a", "b"], globalResultCapReached: false
        )
        precondition(twoClipped.messages == ["2 个站点单页超过 40 条，仅保留每页前 40 条。"])
        print("Native cross-provider search: ordering, concurrency, bounds, failed-key retries, warning reconciliation and cancellation passed")
    }
}
