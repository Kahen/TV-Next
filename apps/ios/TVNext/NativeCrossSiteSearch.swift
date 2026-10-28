import Foundation

/// A bounded native counterpart of the Web type 0/1/2/4 subscription search.
/// The caller must filter out hidden, non-searchable and Spider-only sites.
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

    static func search<Item>(
        sources: [NativeSearchSource],
        concurrency: Int = maxConcurrent,
        fetch: @escaping (NativeSearchSource, Int) async throws -> NativeSearchPage<Item>,
        identity: @escaping (Item) -> String?
    ) async throws -> NativeSearchResult<Item> {
        try Task.checkCancellation()
        var seenSources = Set<String>()
        let eligible = sources.filter { seenSources.insert($0.key).inserted }
        let selected = Array(eligible.prefix(maxSites))
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
                                  warnings: warnings)
    }
}
