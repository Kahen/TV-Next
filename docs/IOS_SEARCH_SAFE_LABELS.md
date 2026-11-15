# iOS cross-site search: untrusted provider labels

Imported FongMi site names are presentation data, not provider identities. A nonblank name containing a control character, Unicode format scalar (including bidi overrides and zero-width markers), U+2028 or U+2029 now falls back to its validated opaque provider key in search failure feedback and selected-provider labels. A blank/whitespace-only name also falls back to the key.

Ordinary Unicode names, accents and meaningful surrounding spaces are preserved exactly. Provider keys, request fan-out, search deduplication, failure retry and source order are unchanged.

## Verification

- XCTest: `CrossSiteRetryTests.testUntrustedProviderDisplayNamesFallbackWithoutChangingRetryIdentity` checks negative labels, legitimate labels, failed search and exact-key retry.
- Standalone Swift: `apps/ios/tests/CrossSiteSearchSmoke.swift` checks an owned spoofed-label failure.
- Required before merge: final-HEAD iPhone and iPad simulator XCTest/XCUI, Web/API and complete integration gate.

This is a display integrity guard, not a claim of real-provider compatibility, device acceptance, independent security review or Apple signing. No external streaming source or executable plugin is included.
