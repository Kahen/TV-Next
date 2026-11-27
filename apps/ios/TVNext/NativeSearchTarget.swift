import Foundation

/// Limits native cross-site requests to a user-selected, currently eligible provider.
/// An invalid/stale selection must never silently expand to all providers.
enum NativeSearchTarget {
    static let all = ""

    static func eligible(_ sources: [NativeSearchSource]) -> [NativeSearchSource] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0.key).inserted }
            .filter { NativeCrossSiteSearch.selectedSourceKeys([$0]).count == 1 }
    }

    static func resolve(_ sources: [NativeSearchSource], selectedKey: String) -> [NativeSearchSource] {
        let candidates = eligible(sources)
        if selectedKey == all { return Array(candidates.prefix(NativeCrossSiteSearch.maxSites)) }
        return candidates.filter { $0.key == selectedKey }
    }
}
