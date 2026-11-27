import Foundation

/// A presentation-only filter. Provider provenance remains attached to each hit,
/// and changing the filter never alters the underlying search/retry snapshot.
extension NativeCrossSiteResultFilter {
    static func visible<Item>(
        _ hits: [NativeSearchHit<Item>],
        selectedKey: String,
        searchedKeys: [String]
    ) -> [NativeSearchHit<Item>] {
        let key = reconciledSelection(selectedKey, searchedKeys: searchedKeys)
        return key.isEmpty ? hits : hits.filter { $0.siteKey == key }
    }

    static func reconciledSelection(_ selectedKey: String, searchedKeys: [String]) -> String {
        selectedKey.isEmpty || searchedKeys.contains(selectedKey) ? selectedKey : ""
    }
}
