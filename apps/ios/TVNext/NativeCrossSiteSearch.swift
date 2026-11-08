import Foundation

/// A bounded native counterpart of the Web type 0/1/2/4 subscription search.
/// The caller filters hidden/unsearchable sites and checks server-approved Spider capability and device login.
struct NativeSearchSource: Hashable {
    let key: String
    let name: String
}

struct NativeSearchPage<Item> {
    let items: [Item]
    let hasMore: Bool
}

struct NativeSearchHit<Item> {
    let siteKey: String
    let item: Item
}

/// Typed warning provenance; a localized message is not a provider identity.
struct NativeSearchWarningState: Sendable {
    let omittedSiteCount: Int
    let pageLimitKeys: Set<String>
    let clippedPageKeys: Set<String>
    let globalResultCapReached: Bool

    static let empty = NativeSearchWarningState(
        omittedSiteCount: 0, pageLimitKeys: [], clippedPageKeys: [],
        globalResultCapReached: false
    )

    var messages: [String] {
        var warnings: [String] = []
        if omittedSiteCount > 0 {
            warnings.append("仅搜索前 \(NativeCrossSiteSearch.maxSites) 个可用站点，其余 \(omittedSiteCount) 个未请求。")
        }
        if !pageLimitKeys.isEmpty {
            warnings.append("\(pageLimitKeys.count) 个站点仍有更多结果；每站最多检索 \(NativeCrossSiteSearch.maxPages) 页。")
        }
        if !clippedPageKeys.isEmpty {
            warnings.append("\(clippedPageKeys.count) 个站点单页超过 \(NativeCrossSiteSearch.maxItemsPerPage) 条，仅保留每页前 \(NativeCrossSiteSearch.maxItemsPerPage) 条。")
        }
        if globalResultCapReached {
            warnings.append("仅显示前 \(NativeCrossSiteSearch.maxResults) 条结果。")
        }
        return warnings
    }

    /// Failed-again providers retain their previous partial hits and warnings.
    /// A prior global cap remains conservative: discarded overflow cannot be
    /// reconstructed without requerying already successful providers.
    func replacingRecoveredProviders(with retry: Self, recoveredKeys: Set<String>) -> Self {
        NativeSearchWarningState(
            omittedSiteCount: omittedSiteCount,
            pageLimitKeys: pageLimitKeys.subtracting(recoveredKeys)
                .union(retry.pageLimitKeys.intersection(recoveredKeys)),
            clippedPageKeys: clippedPageKeys.subtracting(recoveredKeys)
                .union(retry.clippedPageKeys.intersection(recoveredKeys)),
            globalResultCapReached: globalResultCapReached || retry.globalResultCapReached
        )
    }
}

struct NativeSearchResult<Item> {
    let items: [NativeSearchHit<Item>]
    let failed: [String]
    /// Stable provider keys, never display names (which may collide).
    let failedKeys: [String]
    let warningState: NativeSearchWarningState
    var warnings: [String] { warningState.messages }
}

private struct NativeSearchOutcome<Item> {
    let index: Int
    let hits: [NativeSearchHit<Item>]
    let failed: Bool
    let truncated: Bool
    let clippedPage: Bool
}

enum NativeCrossSiteSearch {
    static let maxSites = 16
    static let maxConcurrent = 4
    static let maxPages = 2
    static let maxItemsPerPage = 40
    static let maxResults = 600

    /// Match the coordinator's first-unique-provider selection, including
    /// subscriptions that repeat a key before the 16-site boundary.
    static func selectedSources(_ sources: [NativeSearchSource]) -> [NativeSearchSource] {
        var seen = Set<String>()
        return Array(sources.filter { source in
            // Empty/whitespace-only provider keys cannot identify a retry target.
            // Reject them before they consume one of the bounded search slots.
            !source.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                seen.insert(source.key).inserted
        }.prefix(maxSites))
    }

    /// Explicit completion feedback: no matches is different from transport failure.
    /// Never show an empty state while a search is pending or before any site ran;
    /// the caller owns the completion flag and the original selected-site count.
    static func emptyState(resultCount: Int, failedCount: Int, selectedCount: Int) -> String? {
        guard selectedCount > 0, resultCount == 0, failedCount >= 0 else { return nil }
        if failedCount >= selectedCount { return "所有站点搜索失败，请重试失败站点。" }
        if failedCount > 0 { return "尚无匹配结果，部分站点搜索失败，可重试。" }
        return "未找到匹配结果。"
    }

    static func selectedSourceKeys(_ sources: [NativeSearchSource]) -> [String] {
        selectedSources(sources).map(\.key)
    }

    static func selectedSourceNames(_ sources: [NativeSearchSource]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: selectedSources(sources).map { ($0.key, $0.name) })
    }

    /// Retry only keys that actually participated in the original bounded
    /// search. Resolve against the currently authorized/visible list, never
    /// the raw subscription (where a hidden duplicate could shadow a site).
    /// Apply the same first-16-unique boundary as the initial search before
    /// filtering failed keys: a stale/foreign key must not expand fan-out.
    static func failedOnlySources(
        _ eligible: [NativeSearchSource],
        failedKeys: [String],
        searchedKeys: [String]
    ) -> [NativeSearchSource] {
        let originallySearched = Set(validSourceOrder(searchedKeys))
        let requested = Set(failedKeys).intersection(originallySearched)
        return selectedSources(eligible).filter { requested.contains($0.key) }
    }

    /// Ignore malformed and repeated snapshot keys before applying the search cap.
    /// A corrupt first entry must not consume one of the original 16 slots.
    private static func validSourceOrder(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return Array(keys.filter { key in
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                seen.insert(key).inserted
        }.prefix(maxSites))
    }

    /// Reconcile a failed-site retry with the last visible search. Successful
    /// providers are never re-fetched or discarded; a recovered provider
    /// atomically replaces its old partial page. A provider that fails again
    /// retains its previous partial hits instead of showing a mixed snapshot.
    /// Rebuild in original provider order, with per-provider identity dedupe.
    static func mergeRetry<Item>(
        previous: [NativeSearchHit<Item>],
        refreshed: [NativeSearchHit<Item>],
        recoveredKeys: Set<String>,
        sourceOrder: [String],
        identity: (Item) -> String?
    ) -> [NativeSearchHit<Item>] {
        let orderedKeys = validSourceOrder(sourceOrder)
        let permitted = Set(orderedKeys)
        // A retry must not turn a malformed or oversized caller snapshot into
        // unbounded retained memory. A normal search returns at most two pages
        // of 40 hits per provider; keep that same bound during reconciliation.
        let maxHitsPerSource = maxPages * maxItemsPerPage
        var grouped: [String: [NativeSearchHit<Item>]] = [:]
        var seenBySource: [String: Set<String>] = [:]
        // Apply the limit to distinct, valid identities rather than raw entries:
        // a malformed or duplicate leading page must not evict later valid hits.
        func retain(_ hit: NativeSearchHit<Item>) {
            guard let id = identity(hit.item), !id.isEmpty,
                  grouped[hit.siteKey, default: []].count < maxHitsPerSource,
                  seenBySource[hit.siteKey, default: []].insert(id).inserted else { return }
            grouped[hit.siteKey, default: []].append(hit)
        }
        for hit in previous where permitted.contains(hit.siteKey) && !recoveredKeys.contains(hit.siteKey) {
            retain(hit)
        }
        for hit in refreshed where permitted.contains(hit.siteKey) && recoveredKeys.contains(hit.siteKey) {
            retain(hit)
        }
        var merged: [NativeSearchHit<Item>] = []
        var visited = Set<String>()
        for key in orderedKeys where visited.insert(key).inserted {
            for hit in grouped[key] ?? [] {
                merged.append(hit)
                if merged.count == maxResults { return merged }
            }
        }
        return merged
    }

    static func search<Item>(
        sources: [NativeSearchSource],
        concurrency: Int = maxConcurrent,
        fetch: @escaping (NativeSearchSource, Int) async throws -> NativeSearchPage<Item>,
        identity: @escaping (Item) -> String?
    ) async throws -> NativeSearchResult<Item> {
        try Task.checkCancellation()
        var seenSources = Set<String>()
        let eligible = sources.filter { source in
            !source.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                seenSources.insert(source.key).inserted
        }
        let selected = selectedSources(eligible)
        var grouped = Array(repeating: [NativeSearchHit<Item>](), count: selected.count)
        var failures = Set<Int>()
        var truncated = Set<Int>()
        var clippedPages = Set<Int>()

        let parallel = min(maxConcurrent, max(1, concurrency))
        // Bound Android-host fan-out separately; each site's pages stay ordered.
        for offset in stride(from: 0, to: selected.count, by: parallel) {
            try Task.checkCancellation()
            let batch = Array(selected.enumerated())[offset..<min(offset + parallel, selected.count)]
            await withTaskGroup(of: NativeSearchOutcome<Item>.self) { group in
                for (index, source) in batch {
                    group.addTask {
                        var hits: [NativeSearchHit<Item>] = []
                        var seenItems = Set<String>()
                        var clippedPage = false
                        for number in 1...maxPages {
                            if Task.isCancelled { return NativeSearchOutcome(index: index, hits: [], failed: false, truncated: false, clippedPage: false) }
                            do {
                                let response = try await fetch(source, number)
                                if Task.isCancelled { return NativeSearchOutcome(index: index, hits: [], failed: false, truncated: false, clippedPage: false) }
                                // A provider can return >40 entries even with hasMore=false.
                                // Report this separate truncation; it is not another page.
                                clippedPage = clippedPage || response.items.count > maxItemsPerPage
                                for item in response.items.prefix(maxItemsPerPage) {
                                    guard let id = identity(item), !id.isEmpty, seenItems.insert(id).inserted else { continue }
                                    hits.append(NativeSearchHit(siteKey: source.key, item: item))
                                }
                                if !response.hasMore { return NativeSearchOutcome(index: index, hits: hits, failed: false, truncated: false, clippedPage: clippedPage) }
                                if number == maxPages { return NativeSearchOutcome(index: index, hits: hits, failed: false, truncated: true, clippedPage: clippedPage) }
                            } catch {
                                return NativeSearchOutcome(index: index, hits: hits, failed: !Task.isCancelled, truncated: false, clippedPage: clippedPage)
                            }
                        }
                        return NativeSearchOutcome(index: index, hits: hits, failed: false, truncated: false, clippedPage: clippedPage)
                    }
                }
                for await outcome in group {
                    grouped[outcome.index] = outcome.hits
                    if outcome.failed { failures.insert(outcome.index) }
                    if outcome.truncated { truncated.insert(outcome.index) }
                    if outcome.clippedPage { clippedPages.insert(outcome.index) }
                }
            }
        }
        try Task.checkCancellation()
        let all = grouped.flatMap { $0 }
        let warningState = NativeSearchWarningState(
            omittedSiteCount: max(0, eligible.count - maxSites),
            pageLimitKeys: Set(selected.enumerated().compactMap {
                truncated.contains($0.offset) ? $0.element.key : nil
            }),
            clippedPageKeys: Set(selected.enumerated().compactMap {
                clippedPages.contains($0.offset) ? $0.element.key : nil
            }),
            globalResultCapReached: all.count > maxResults
        )
        return NativeSearchResult(items: Array(all.prefix(maxResults)),
                                  failed: selected.enumerated().compactMap { failures.contains($0.offset) ? $0.element.name : nil },
                                  failedKeys: selected.enumerated().compactMap { failures.contains($0.offset) ? $0.element.key : nil },
                                  warningState: warningState)
    }
}
