# Native iOS cross-provider search: failed-only retry

Status: P2 implementation slice #144; **not** real-provider or physical-device acceptance.

## Behavior

After a FongMi subscription has been loaded, a native iPhone/iPad user can search all eligible sites. The existing search coordinator caps requests to 16 distinct providers, at most four concurrently (two for Android-host-capable configurations), two pages per site, 40 entries per page and 600 visible results.

If one or more providers fail, the results from successful providers stay visible. The failure message exposes **重试失败站点**. The retry uses the original submitted keyword, not subsequent text-field edits, and sends requests only to failed provider **keys**. Provider display names are not routing identifiers and may collide. Failed keys are resolved against the already eligible, visible, supported provider list rather than the raw subscription, so an earlier hidden/unsupported duplicate key cannot shadow the provider that was searched.

A recovered provider replaces its previous partial page, deduplicated by media ID within that provider, and results are reordered by the original provider order. A provider that fails again keeps its prior partial hits. The retry control disappears when no failed keys remain. New subscription loads, browsing, site detail changes, server/session changes and view disappearance clear the previous search context; generation and task cancellation prevent stale callbacks from changing results.

No subscription content, provider credentials or search results are persisted by this feature. The retry is an explicit user action and does not add automatic request storms, remote plugin execution or new network endpoints.

## Synthetic acceptance

- `apps/ios/tests/CrossSiteSearchSmoke.swift`: key/name collision, only failed providers requested, original keyword, partial recovery, duplicate/foreign hits, original ordering and 600-result boundary.
- `apps/ios/tests/unit/CrossSiteRetryTests.swift`: XCTest positive/negative reconciliation and provider-key failure identity.
- `scripts/cross_site_retry_fixture_server.py`: owned loopback-only FongMi-shaped `subscriptions/load` and `subscriptions/search` responses. Provider A succeeds; provider B fails once, then succeeds only when retried with the original keyword. A second A request is rejected.
- `scripts/test_cross_site_retry_fixture_server.py`: fixture request validation and positive/negative retry behavior.
- `apps/ios/tests/ui/LibraryUITests.swift`: production SwiftUI XCUI loads the fixture, searches, edits the draft keyword, retries and verifies A remains while B appears and the retry control disappears.
- `.github/workflows/ios.yml`: run Swift smoke, Python fixture unit tests, unsigned simulator builds, XCTest and XCUI for iPhone/iPad. The final PR HEAD must also pass the complete Web/API/PostgreSQL/Compose/NAS/Spider isolation gate.

## Exclusions

This does not expand FongMi provider protocol support or make type-3 Android Spider/JAR/JS/Python execution safe. The fixture is entirely synthetic; it is not a lawful external-provider compatibility corpus. Real provider latency/authentication, real iPhone/iPad networking, Apple distribution signing, security audit and P2/P3/P6 milestone acceptance remain unverified. Never bundle unapproved streaming sources or remote code.

## Eligible provider provenance regression (#146)

The result label is bound to a snapshot of the **actually eligible, selected** provider keys and names, not the first matching key in the unfiltered subscription. Hidden or unsupported entries that reuse a later visible provider key cannot masquerade as the displayed source. The snapshot follows the same first-eligible-key and 16-provider cap as search and retry; it is cleared when search context resets and is not persisted.

Synthetic regression: Swift smoke and XCTest check duplicate eligible keys, unknown keys and the 16-provider boundary. The owned loopback fixture now returns a hidden `b` ("Hidden Spoof") before visible `a`/`b` (both "Mirror"). Production iPhone/iPad XCUI asserts the recovered `B result · Mirror` label and rejects the hidden name. Final-head aggregate CI is required before merging; this does not prove provider authenticity, real-device compatibility or independent security review.
