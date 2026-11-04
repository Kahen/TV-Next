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

## Explicit completion and empty-state feedback (#148)

After an eligible cross-site search actually completes, native SwiftUI distinguishes a successful zero-hit result (**未找到匹配结果。**) from no hits with some provider failures (**尚无匹配结果，部分站点搜索失败，可重试。**) or all providers failing (**所有站点搜索失败，请重试失败站点。**). The message is not shown before a search, during the initial pending request or when there are hits. Retrying recomputes the status without discarding previous partial hits; new subscription loads, browsing and session/server changes clear it. This is UI feedback, not a provider reachability guarantee.

Synthetic validation includes pure Swift smoke/XCTest boundaries, an owned localhost `no-results` query with both providers returning HTTP 200 and zero items, Python fixture tests and production SwiftUI iPhone/iPad XCUI for success, no retry and reload reset. Final HEAD Web/API and full integration CI must pass before merging. Physical Apple hardware, real providers, security audit, lawful Spider corpus and signing remain unverified.

## Oversized terminal-page visibility (#156)

A FongMi-compatible provider may return more than 40 entries in a single search response while declaring `hasMore=false`. Previously the native coordinator kept the first 40 silently, because its warning only described additional pages beyond the second. The iOS UI now reports **单页超过 40 条，仅保留每页前 40 条** for each affected provider. This is distinct from **仍有更多结果**, which is emitted only if the second page still advertises another page. Both warnings may coexist. Provider failures preserve any earlier clipping warning, but upstream exception text and credentials are never surfaced.

The original 16-unique-site, 4-concurrent, 2-page/site, 40-item/page and 600-visible-item limits are unchanged. The warning does not fetch additional pages or infer whether a provider omitted results on its own. Synthetic 40/41-item, `hasMore`, second-page failure and owned loopback 41-item terminal-page tests run in Swift smoke/XCTest, Python and production iPhone/iPad XCUI. Merge only after final-HEAD full integration success; physical devices and authorized external provider behavior remain unverified.


## Reconcile warning provenance after failed-only retry (#158)

Warnings for page-count and per-page clipping are tracked by the stable selected provider **key**, not by deduplicating Chinese message strings. When retry succeeds, that provider's previous partial results and its old warning state are both replaced. When retry fails again, retained old partial results keep their old warning state. Healthy providers are not queried or cleared, and two distinct clipped providers are counted as two. The original site-cap warning remains; a previously reached global 600-result cap is conservatively retained because discarded overflow cannot be reconstructed without requerying healthy providers. New searches reset warning state.

Swift smoke/XCTest, a localhost page-1-clipped/page-2-failed/retry-success fixture, Python unit tests and production iPhone/iPad XCUI cover the change. This is not an authorized external provider corpus, physical-device acceptance, security audit or release evidence.


## Retry boundary and original selection snapshot (#168)

Failed-only retry is now restricted to the **originally searched provider keys** and to the first 16 distinct entries of the current authorized/visible list. A stale or foreign failure key, including an eligible 17th provider, cannot cause a new search request. A newly inserted eligible site cannot enter a retry simply because the current list shifted; a displaced old site also fails closed. Duplicate keys retain the first eligible provider identity. The original submitted keyword, healthy-site results and existing partial-failure reconciliation are unchanged.

Swift smoke and XCTest exercise 16/17 boundaries, changed eligible lists, duplicate keys, stale keys and actual retry request counts. Existing production SwiftUI iPhone/iPad XCUI, unsigned simulator build and full cross-platform gate remain required on final HEAD. These are synthetic checks, not physical-device or real-provider acceptance.
