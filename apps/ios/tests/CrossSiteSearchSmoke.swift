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
            eligibleForRetry, failedKeys: ["b", "missing", "b"])
        precondition(failedOnly.map(\.key) == ["b"])
        precondition(failedOnly.map(\.name) == ["Visible B"])
        precondition(NativeCrossSiteSearch.failedOnlySources(
            eligibleForRetry, failedKeys: ["unknown"]).isEmpty)

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
        // The 600-result global cap still applies after recovered sites expand.
        let many = (0..<700).map { NativeSearchHit(siteKey: "b", item: Item(id: String($0))) }
        let cappedRetry = NativeCrossSiteSearch.mergeRetry(
            previous: first.items, refreshed: many, recoveredKeys: ["b"],
            sourceOrder: ["a", "b", "c"], identity: { $0.id }
        )
        precondition(cappedRetry.count == 600)
        precondition(cappedRetry.first?.item.id == "a-old")
        precondition(cappedRetry.last?.item.id == "598")

        print("Native cross-provider search: ordering, concurrency, bounds, failed-key retries, stable partial results and cancellation passed")
    }
}
