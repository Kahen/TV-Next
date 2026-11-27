# Native SMB directory enumeration model

This increment adds `NativeSMBDirectoryEntry` and `NativeSMBDirectoryPage` for future authenticated SMB2/3 enumeration. It does **not** establish a network SMB session or expose a directory browser.

The model rejects traversal components, slash/backslash/colon separators, controls and Unicode format characters, oversized UTF-8 names, negative sizes and directory entries with nonzero file sizes. A directory page is capped at 512 entries and rejects ambiguous case/diacritic-insensitive duplicates. It preserves valid Unicode and sorts folders first with natural filename ordering.

A future SMB transport must enumerate pages without truncation, resolve continuation tokens safely, authenticate via a credential store, and map file reads into the bounded read-range model. Do not interpolate these names into shell commands or URLs without separate encoding and root-confinement checks.

Tests: `NativeSMBDirectoryPageTests` covers ordering, valid Unicode, traversal, separators, duplicate names and bounds. Full iOS XCTest and simulator builds require macOS/Xcode; no physical SMB compatibility is claimed.
