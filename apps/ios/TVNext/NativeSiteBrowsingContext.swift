import Foundation

/// Site-owned category/filter state must never leak across cross-provider results.
/// This is a value type so the transition can be exercised without SwiftUI or a server.
struct NativeSiteBrowsingContext<Filter> {
    var siteKey: String
    var category: String?
    var mode: String
    var filterCatalog: [String: [Filter]]
    var filters: [String: String]
    var appliedFilters: [String: String]

    /// Returns true only when switching providers; same-site detail retains filters.
    @discardableResult
    mutating func switchToDetailSite(_ key: String) -> Bool {
        guard key != siteKey else { return false }
        siteKey = key
        category = nil
        mode = "home"
        filterCatalog = [:]
        filters = [:]
        appliedFilters = [:]
        return true
    }
}
