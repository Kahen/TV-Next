# Native cross-site search: blank provider labels

The imported FongMi provider key remains the exact, validated opaque identity used for selection, results and failed-only retry. A provider name consisting only of whitespace is not useful as an error label. Native search now displays its key instead in the selected-provider name snapshot and failed-provider list. Nonblank names, including meaningful surrounding spaces and Unicode, are preserved exactly.

This is a display-only fallback; it does not change search fan-out, subscription parsing, credentials, source approval or retry identity. XCTest checks blank names and nonblank Unicode/spacing; standalone Swift smoke checks failed-provider feedback. Final-head iPhone/iPad simulator and full integration gates are required before merge. Real FongMi providers and physical Apple devices are not verified by these fixtures.

## UTF-8 display-name bound

Untrusted provider display names longer than 256 UTF-8 bytes now fall back to the validated opaque provider key. This applies to selected-source labels and failed-provider summaries; the key itself remains unchanged for initial search and failed-only retry. Valid nonblank ASCII and multibyte Unicode labels within the bound remain intact. XCTest covers both boundaries, failure labels and retry identity. This does not establish real-provider or physical-device compatibility.
