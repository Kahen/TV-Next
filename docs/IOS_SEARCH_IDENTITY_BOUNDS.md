# Native cross-site search identity byte bounds

The native FongMi cross-site search accepts provider keys up to **1,024 UTF-8 bytes** and opaque result IDs up to **4,096 UTF-8 bytes**. Longer values are rejected rather than truncated, because truncation could alias distinct providers or results. The original identity and meaningful Unicode/spacing remain unchanged within the limit. Existing rejection of blank, control, format, and Unicode line/paragraph separators remains in force.

The same rules apply to first-pass selection, page deduplication, failed-provider retry selection, and retry reconciliation. Invalid entries do not consume the 16-provider, 40-distinct-items-per-page, or 80-distinct-items-per-provider caps. This deliberately narrows compatibility for exceptionally long opaque identifiers; real provider compatibility has not been established.

## Regression and release gates

`CrossSiteSearchSmoke.swift` and `CrossSiteRetryTests.swift` cover oversized and valid multibyte Unicode identities in initial selection/search and retry. Final PR HEAD must pass iPhone and iPad simulator XCTest/XCUI, independent Web/API CI and full integration (including NAS/Compose/Spider isolation) before merging. No remote plugin, external source, physical-device validation, Apple signing or release is part of this change.
