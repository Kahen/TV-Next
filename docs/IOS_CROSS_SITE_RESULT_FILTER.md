# Native cross-site result filtering

The iPhone/iPad subscription screen now filters the **already loaded** cross-provider search hits by media title or the selected provider's display name. The query is trimmed and uses locale-aware standard matching. Empty input restores the complete result set; the counter shows visible versus loaded hits.

This does not issue provider requests, modify the original provider key or media ID, alter failed-provider retry snapshots, or persist the filter. Selecting a filtered hit still uses its original site key for detail/play routing. Starting a new cross-site search, switching context or leaving the view clears the filter. This is not server-side search or a claim of complete provider coverage.

Unit regressions cover Unicode title matching, case-insensitive provider matching, empty/no-match queries, original order, and duplicate media IDs across different providers. Run the native XCTest suite on Xcode CI before merging; local Linux does not provide the iOS app SDK.
