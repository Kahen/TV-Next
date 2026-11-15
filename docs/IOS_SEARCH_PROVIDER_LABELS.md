# Native cross-site search: blank provider labels

The imported FongMi provider key remains the exact, validated opaque identity used for selection, results and failed-only retry. A provider name consisting only of whitespace is not useful as an error label. Native search now displays its key instead in the selected-provider name snapshot and failed-provider list. Nonblank names, including meaningful surrounding spaces and Unicode, are preserved exactly.

This is a display-only fallback; it does not change search fan-out, subscription parsing, credentials, source approval or retry identity. XCTest checks blank names and nonblank Unicode/spacing; standalone Swift smoke checks failed-provider feedback. Final-head iPhone/iPad simulator and full integration gates are required before merge. Real FongMi providers and physical Apple devices are not verified by these fixtures.
