# Native cloud directory refresh and session invalidation

The iPhone/iPad AList/OpenList directory view now offers **刷新当前目录**. It reissues `cloud/list` for the currently displayed path and page, retaining the existing cancellation/revision guard. A page label makes the refreshed page visible.

Editing the cloud endpoint, access token or directory password immediately cancels in-flight requests, invalidates the current listing and clears old errors. This prevents selecting a stale listing with newly edited credentials. Explicit disconnect and leaving the view also clear token/password memory. The server-side API remains responsible for authorization.

Previous/next controls use `NativeCloudPageNavigation` to reject invalid page indices and integer overflow. XCTest covers normal transitions, first/last pages, invalid negative/zero values and `Int.max`. Xcode simulator and full CI have not been executed in this change; concurrent cloud UI PRs require conflict resolution before merge.
