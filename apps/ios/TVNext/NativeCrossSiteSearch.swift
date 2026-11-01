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

struct NativeSearchResult<Item> {
    let items: [NativeSearchHit<Item>]
    let failed: [String]
    /// Stable provider keys, never display names (which may collide).
    let failedKeys: [String]
    let warnings: [String]
}

private struct NativeSearchOutcome<Item> {
    let index: Int
    let hits: [NativeSearchHit<Item>]
    let failed: Bool
    let truncated: Bool
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
        return Array(sources.filter { seen.insert($0.key).inserted }.prefix(maxSites))
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

    /// Select only previously failed provider keys from the caller's already
    /// authorized/visible site list. Do not resolve a key against an unfiltered
    /// subscription: an earlier hidden or unsupported duplicate may otherwise
    /// shadow the eligible site that actually participated in the search.
    static func failedOnlySources(_ eligible: [NativeSearchSource], failedKeys: [String]) -> [NativeSearchSource] {
        let requested = Set(failedKeys)
        var seen = Set<String>()
        return eligible.filter { requested.contains($0.key) && seen.insert($0.key).inserted }
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
        let permitted = Set(sourceOrder.prefix(maxSites))
        var grouped: [String: [NativeSearchHit<Item>]] = [:]
        for hit in previous where permitted.contains(hit.siteKey) && !recoveredKeys.contains(hit.siteKey) {
            grouped[hit.siteKey, default: []].append(hit)
        }
        for hit in refreshed where permitted.contains(hit.siteKey) && recoveredKeys.contains(hit.siteKey) {
            grouped[hit.siteKey, default: []].append(hit)
        }
        var merged: [NativeSearchHit<Item>] = []
        var visited = Set<String>()
        for key in sourceOrder.prefix(maxSites) where visited.insert(key).inserted {
            var seen = Set<String>()
            for hit in grouped[key] ?? [] {
                guard let id = identity(hit.item), !id.isEmpty, seen.insert(id).inserted else { continue }
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
        let eligible = sources.filter { seenSources.insert($0.key).inserted }
        let selected = selectedSources(eligible)
        var grouped = Array(repeating: [NativeSearchHit<Item>](), count: selected.count)
        var failures = Set<Int>()
        var truncated = Set<Int>()

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
                        for number in 1...maxPages {
                            if Task.isCancelled { return NativeSearchOutcome(index: index, hits: [], failed: false, truncated: false) }
                            do {
                                let response = try await fetch(source, number)
                                if Task.isCancelled { return NativeSearchOutcome(index: index, hits: [], failed: false, truncated: false) }
                                for item in response.items.prefix(maxItemsPerPage) {
                                    guard let id = identity(item), !id.isEmpty, seenItems.insert(id).inserted else { continue }
                                    hits.append(NativeSearchHit(siteKey: source.key, item: item))
                                }
                                if !response.hasMore { return NativeSearchOutcome(index: index, hits: hits, failed: false, truncated: false) }
                                if number == maxPages { return NativeSearchOutcome(index: index, hits: hits, failed: false, truncated: true) }
                            } catch {
                                return NativeSearchOutcome(index: index, hits: hits, failed: !Task.isCancelled, truncated: false)
                            }
                        }
                        return NativeSearchOutcome(index: index, hits: hits, failed: false, truncated: false)
                    }
                }
                for await outcome in group {
                    grouped[outcome.index] = outcome.hits
                    if outcome.failed { failures.insert(outcome.index) }
                    if outcome.truncated { truncated.insert(outcome.index) }
                }
            }
        }
        try Task.checkCancellation()
        let all = grouped.flatMap { $0 }
        var warnings: [String] = []
        if eligible.count > maxSites { warnings.append("仅搜索前 \(maxSites) 个可用站点，其余 \(eligible.count - maxSites) 个未请求。") }
        if !truncated.isEmpty { warnings.append("\(truncated.count) 个站点仍有更多结果；每站最多检索 \(maxPages) 页。") }
        if all.count > maxResults { warnings.append("仅显示前 \(maxResults) 条结果。") }
        return NativeSearchResult(items: Array(all.prefix(maxResults)),
                                  failed: selected.enumerated().compactMap { failures.contains($0.offset) ? $0.element.name : nil },
                                  failedKeys: selected.enumerated().compactMap { failures.contains($0.offset) ? $0.element.key : nil },
                                  warnings: warnings)
    }
}
