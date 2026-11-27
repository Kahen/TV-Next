# Native cloud directory filtering

The iPhone/iPad AList/OpenList directory view now filters the currently loaded page by file or folder name, ignoring case and trimming surrounding query whitespace. Results are sorted with directories first and natural localized filename ordering. Changing directory clears the filter; paging within a directory preserves it.

This is **local filtering only**, not server-side search: a match on another page will not appear until that page is loaded. Credentials and search terms are not sent to a new endpoint. Empty matches do not delete files or alter the provider listing. The existing cloud playback and path safety policies remain unchanged.

Unit regressions: `NativeCloudListingFilterTests.swift` covers directory-first/natural ordering, case-insensitive search, whitespace and no-match behavior. Requires iOS XCTest/Xcode; no physical device or external cloud credentials are needed.
