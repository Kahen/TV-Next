import Foundation

/// A presentation-only filter. Provider provenance remains attached to each hit,
/// and changing the filter never alters the underlying search/retry snapshot.
enum NativeCrossSiteResultFilter {
    static func visible<Item>(
        _ hits: [NativeSearchHit<Item>],
        selectedKey: String,
        searchedKeys: [String]
    ) -> [NativeSearchHit<Item>] {
        guard !selectedKey.isEmpty else { return hits }
        guard searchedKeys.contains(selectedKey) else { return hits }
        return hits.filter { $0.siteKey == selectedKey }
    }

    static func reconciledSelection(_ selectedKey: String, searchedKeys: [String]) -> String {
        selectedKey.isEmpty || searchedKeys.contains(selectedKey) ? selectedKey : ""
    }
}
