# Native FongMi search query snapshot

A provider search submits the trimmed editor text on page one. Once the response is current and successful, its submitted keyword is recorded. Next/previous page and search refresh reuse that keyword even when the search field has been edited. A new page-one search submits the latest draft. Changing site or leaving search mode clears the committed keyword.

This prevents a user from accidentally mixing pages from different searches and keeps retry/refresh semantics deterministic. Existing cancellation and generation guards still decide whether a response can update the UI.

Tests: `NativeSearchQuerySnapshotTests` covers unchanged pagination, fresh search, cross-site isolation, missing snapshots and empty snapshots. Full iOS simulator and Xcode build remain unverified here.
