# Implementation status — 2026-11-14

> **2026-11-14 native search page-cap correctness (PR pending):** A single provider page now counts up to 40 valid distinct result identities instead of blindly taking the first 40 raw entries. Invalid or repeated entries no longer hide later valid results. The existing raw-page clipping warning remains conservative. Added XCTest and standalone Swift positive/negative regression. Final HEAD iPhone/iPad simulators and full integration gate required; real providers and physical devices remain unverified.\n\n
> **2026-11-14 native search Unicode separator boundary (pending CI):** Native provider keys and opaque result IDs now reject Unicode U+2028 line separator and U+2029 paragraph separator as well as existing controls/format markers, preventing visually split provider/result identities in initial search and failed-only retry. Meaningful Unicode and ordinary spaces remain unchanged. Added positive/negative XCTest and standalone Swift smoke. Final source HEAD iPhone/iPad simulator, Web/API and complete integration gates are required before merge. No real-provider, physical-device, independent security review or Apple distribution claim.

> **2026-11-13 integration-gate correction:** PR #196 merged as `9bede9f3` after [final-head full integration 9/9](https://github.com/Kahen/TV-Next/actions/runs/43283088656). PR #197 merged as `2df3a250` after [final-head full integration 9/9](https://github.com/Kahen/TV-Next/actions/runs/43396390404), including iPhone/iPad simulator checks. These results validate their respective PR heads only; this documentation PR requires its own final-head gate. Physical devices, third-party Spider corpus and Apple distribution remain unverified.

> **2026-11-12 status reconciliation:** PRs [#192](https://github.com/Kahen/TV-Next/pull/192), [#193](https://github.com/Kahen/TV-Next/pull/193) and [#194](https://github.com/Kahen/TV-Next/pull/194) are merged, not awaiting CI. PR #194 final source HEAD `aaa59747` passed [full integration 9/9](https://github.com/Kahen/TV-Next/actions/runs/43143373090) and [Web/API 3/3](https://github.com/Kahen/TV-Next/actions/runs/43143373119); main merge is `34ceefdc`. Earlier 'await CI' statements in dated entries below describe historical pre-merge states. This does not validate physical iPhone/iPad, real external providers, independent security review or Apple distribution. P2 #3 remains open.


> **2026-11-12 native result identity hardening (PR #194 merged):** Initial cross-site search and failed-provider retry reject result identities containing Unicode control (`Cc`) or format (`Cf`) scalars, including embedded NUL, newline, zero-width and bidi override characters. Exact meaningful Unicode IDs and spacing are preserved. XCTest and standalone Swift smoke cover positive/negative cases. Final-head iPhone/iPad simulator, Web/API and aggregate integration checks are required before merge. No physical-device, real-provider or release claim.

> **2026-11-11 native result identity boundary (PR #193 merged):** Cross-site search and failed-provider retry now reject empty or whitespace-only result identities before deduplication and per-provider limits. Nonblank Unicode identities remain unchanged. Added XCTest positive/negative cases and standalone Swift smoke. Await final-HEAD iPhone/iPad simulator and complete integration checks; no physical-provider compatibility or release claim.

> **2026-11-11 native invisible provider-key guard (PR #192 merged):** Cross-site search now rejects Unicode format (`Cf`) scalars in provider keys, including zero-width and bidirectional override markers, in addition to the prior control-character check. This prevents visually ambiguous keys from entering first-16 selection, failed-only retry, and async requests. Legitimate non-ASCII names/keys remain supported. Added positive and negative XCTest and standalone Swift smoke. Await final-head iPhone/iPad simulator and full integration gates; physical device/provider acceptance remains unverified.


> **2026-11-11 native search key validation (pending final-head CI):** Reject provider keys containing Unicode control characters (including embedded NUL, newline and escape) consistently in initial selection, original-search retry snapshots and async fetch selection. This prevents malformed provider identities from consuming one of 16 slots or entering provider requests. Positive valid-key and negative control-key XCTest plus standalone Swift smoke added. Not a claim of real-provider or device compatibility; merge only after iPhone/iPad simulators and full integration pass.\n\n> **2026-11-11 native search empty-state defensive fix (pending CI):** The iPhone/iPad search feedback helper now rejects an impossible failed-provider count greater than the selected-provider count, rather than incorrectly displaying an all-sites-failed message. Positive all-failed and partial-failed behavior remains unchanged. Added XCTest and standalone Swift smoke negative/boundary cases. This is a local result-state integrity guard, not new FongMi provider compatibility. Final-HEAD iPhone/iPad simulator and full integration checks are required before merge; physical-device acceptance remains #38.


> **2026-11-10 PR #188 follow-up:** The prior final-head [full integration #42770168491](https://github.com/Kahen/TV-Next/actions/runs/42770168491) still failed iPhone/iPad consent-toggle XCUI after moving the toggle above TimelineView. This revision explicitly selects the native SwiftUI switch style and retains the one-tap positive consent assertion, adding a failure-only screenshot and accessibility debug description to distinguish hit-target and model-state failures. This is a hypothesis, not a confirmed root-cause fix. New final HEAD requires iPhone/iPad simulator, Web/API, Compose and complete integration success before merge; physical acceptance #38 remains separate.

> **2026-11-10 PR #188 UI follow-up (pending CI):** The opt-in `automatic-provider-skip` Toggle now precedes the half-second `TimelineView`-driven manual seek control in `NativeProviderSkipControls`. This keeps the consent hit target above the periodically changing player control during XCUI interaction; it is a targeted layout-stability hypothesis, **not** proof that the setter or accessibility issue is fixed. Existing production XCUI checks still require default-off, explicit-on, auto-skip feedback and reset on same-URL episode reload; both iPhone/iPad and all final-HEAD integration jobs must pass before merge. No physical-device claim.

> **2026-11-09 PR #186 merged:** [PR #186](https://github.com/Kahen/TV-Next/pull/186) was merged as main `8e06fe2a` after final source HEAD `8874404e` passed [full integration 9/9](https://github.com/Kahen/TV-Next/actions/runs/42552551431) including iPhone/iPad simulators and [Web/API 3/3](https://github.com/Kahen/TV-Next/actions/runs/42552551386). The earlier pending-merge note below is historical. This does not establish physical-device acceptance.

> **2026-11-09 PR #187 merged:** [PR #187](https://github.com/Kahen/TV-Next/pull/187) bounds native subtitle identity names and language tags to 320/128 UTF-8 bytes in addition to the existing 80/64-character limits. Final HEAD `710055ef` passed [full integration 9/9](https://github.com/Kahen/TV-Next/actions/runs/42575383122) and [Web/API 3/3](https://github.com/Kahen/TV-Next/actions/runs/42575383125). Each iPhone/iPad simulator passed 152 unit and 31 UI tests. Main merge `6d18b1bf`.

> **Source segment playback (pending CI):** Native iPhone/iPad can explicitly enable automatic skipping for the current playback. Web supports manual skipping for the current playback. Both use bounded source ranges and clear the controls when a new episode omits the metadata, even at the same URL. See [IOS_PROVIDER_SKIPS.md](IOS_PROVIDER_SKIPS.md).

> **2026-11-09 proposed iOS control-only subtitle identity guard:** A subtitle display name consisting only of C0 control characters or additional invisible format characters (soft hyphen, ZWNJ, ZWJ) must not become a saved track identity. Meaningful Unicode labels and explicit Off remain supported. Positive/negative XCTest and Swift smoke are included. This is a narrow code fix; final-head iPhone/iPad simulator and full integration results are required before merge. Physical device and provider compatibility remain unverified.

> **Merged historical changes:** PR #184 (native search retry snapshot) and PR #185 (subtitle whitespace/invisible identity) are merged; their earlier pending-CI notes below are historical, not current open PRs.

> **2026-11-08 pending final-head verification (native subtitle identity):** Reject whitespace-only AVPlayer subtitle display names before persisting a per-title track preference. Preserve the exact nonblank display name (including meaningful spacing) for full-identity matching, and preserve explicit Off semantics. Added positive/negative Swift smoke and XCTest coverage. This is an owned-code edge-case fix, not real-provider track or physical-device acceptance; iPhone/iPad simulator and full integration CI must pass before merge.

> **2026-11-08 pending CI (native retry snapshot hardening):** Failed-only retry and hit reconciliation now discard empty/whitespace-only and duplicate original provider keys before enforcing the 16-provider boundary. A malformed snapshot can no longer displace the last valid searched provider or make its partial results disappear. Two XCTest cases cover positive boundary retention and negative foreign-provider injection. This is defensive owned-fixture behavior, not real-provider or device acceptance; final-head iPhone/iPad simulator and complete integration gates are required before merge.

> **Accepted implementation (PR #182):** [PR #182](https://github.com/Kahen/TV-Next/pull/182) merged to main at `10c5578563ab7ed37937e4e335127d01df54587b`. The final source HEAD `aeb1a9ee7f091e1d4a4da024593b4f9c6d9769dd` passed [full integration](https://github.com/Kahen/TV-Next/actions/runs/42339963341) including iPhone/iPad simulators after rerun, and [Web/API CI](https://github.com/Kahen/TV-Next/actions/runs/42339963397). Native iOS offline catalog startup now cleans only generated UUID-named orphan media and partial regular files, preserves unrelated files/directories/symlinks, and rejects a symlinked catalog root before reading its manifest or enumerating orphans. XCTest covers both allowed cleanup and external-file preservation. These checks do **not** establish physical-device behavior or independent security audit. Earlier pending-CI notes below are historical.


> Pending CI: Native cross-site search now rejects empty and whitespace-only provider keys before deduplication and the 16-provider selection cap. This prevents malformed subscription entries from consuming search slots or becoming failed-only retry targets. Added XCTest for selection, retry filtering and actual async fetch. This is not evidence of physical-device or third-party provider compatibility; merge only after final-head iPhone/iPad and full integration gates pass.


> 2026-11-06 follow-up (pending final-head CI): Native iOS failed-provider retry now counts only valid, distinct identities toward the 80-hit per-provider reconciliation cap. Previously 80 duplicate or invalid raw entries could suppress later valid results, unlike initial search deduplication. XCTest and standalone Swift smoke cover duplicate-heavy input, stable ordering, failed-again preservation and foreign-key rejection. This is a code-level fix only; iPhone/iPad simulator and full integration gates must pass before merging. PR #179 is already merged at main `8b725dd0`; earlier “pending PR #179” notes below are historical. No real-provider or physical-device acceptance is implied.\n\nPR #179 final-head follow-up: [full integration 42145414560](https://github.com/Kahen/TV-Next/actions/runs/42145414560) passed iPad, standalone Swift and non-iOS jobs but failed iPhone `testBackgroundAudioTogglePersistsAcrossRelaunch` at the off-to-on assertion. The trace confirms the switch was found and tapped once but its accessibility value remained `0` for five seconds. The test now waits for a stable, enabled, hittable switch frame before each single tap, retaining all persistence assertions. This is a hypothesis about a layout race, not proof of a production fix; final HEAD must pass both simulators and the full gate before merge. If it fails again, investigate the actual SwiftUI binding and persisted store rather than loosening assertions.


> 2026-11-06 pending PR: Native cross-site failed-provider retry reconciliation now retains at most 80 hits per eligible provider (2 pages × 40 items), matching the initial search limits. Unknown keys and failed-again refreshes are still excluded, and original provider ordering is preserved. This is a defensive in-memory bound, not evidence of real-provider compatibility. The PR must pass final-HEAD iPhone/iPad XCTest and full integration before this increment is accepted.

PR #179 regression follow-up: [run 42138922909](https://github.com/Kahen/TV-Next/actions/runs/42138922909) passed iPad and the non-native jobs, but iPhone's DLNA current-media autofill assertion read the text-field placeholder after tapping. The retained recording shows the page shifting during the interaction, while the XCTest trace computes a different button position. After navigation the test now requires a stable, hittable button for one second within a five-second wait, taps once, reveals the actual field and waits at most five seconds for its exact expected URL. The no-media disabled assertion and selected-playback precondition remain; no repeated tap, skipped assertion or workflow timeout increase is added. Final-head full integration remains required.


Source baseline: main `d75d64612b3bfa309ae0af4c8db10343447e9a6f` after merged [PR #175](https://github.com/Kahen/TV-Next/pull/175). Its tree exactly matches tested source `59fff68cafe0187ee7b5ca496144100fa053a9c3`: [full integration](https://github.com/Kahen/TV-Next/actions/runs/41938225257) passed all nine jobs, including 101 API tests with zero failures/errors/skips and 135 unit plus 31 production UI tests on each iPhone/iPad simulator. [Web/API](https://github.com/Kahen/TV-Next/actions/runs/41938225188), [strict JVM integrity](https://github.com/Kahen/TV-Next/actions/runs/41938225191) and [standalone Compose](https://github.com/Kahen/TV-Next/actions/runs/41938225149) also passed. Main-merge checks are tracked separately; these exact source-head results remain the acceptance evidence. Automated owned-fixture results do not establish arbitrary source or physical-device compatibility.

The baseline also contains accepted CI repairs [#172](https://github.com/Kahen/TV-Next/pull/172), JVM maintenance [#93](https://github.com/Kahen/TV-Next/pull/93), reconciled delivery docs #87 and native danmaku/Files/DLNA regressions [#173](https://github.com/Kahen/TV-Next/pull/173). Historical evidence remains [#172 full integration](https://github.com/Kahen/TV-Next/actions/runs/41797242230), [#93 full integration](https://github.com/Kahen/TV-Next/actions/runs/41797558083), [candidate binary comparison](https://github.com/Kahen/TV-Next/actions/runs/41797558092) and [#173 full integration](https://github.com/Kahen/TV-Next/actions/runs/41938097961).

| Phase | Implemented code | Still unfinished |
| --- | --- | --- |
| P1 | Persistent Web/iOS playlists, favorites/history/resume, imports/export/local media, subtitles, speed/fullscreen/PiP, lifecycle handling and PWA shell; implementation #2 closed | Physical iPhone/iPad and installed-PWA acceptance #38 |
| P2 | Type 0/1/2/4 subscription/catalog/filter/detail/episode/search operations; bounded cross-site search, native failed-only retry with original-query/provider provenance, clipping/empty feedback; M3U/TXT/JSON live inputs, XMLTV.gz feeds and bounded replay; native audio/subtitle preferences and opt-in subscription URL Keychain | Interactive QR/login actions, parser/WebView chains, broader Web track preference parity, long-tail replay/provider corpus #3 |
| P3 | Java/Node/Python fixture workers; JAR/DEX preflight; separately compiled, hash-checked owned pure-JVM JAR loaded through original Spider media signatures; OS quotas/cleanup and optional administrator-bound Android bridge | Approved external JVM corpus/dispatcher/egress, real JS/QuickJS/Python adapters, stateful/proxy callbacks, actual ARM Android execution and independent review #4/#45 |
| P4 | Text SRT/VTT/ASS offsets and native overlapping cues; bounded Files/SMB subtitle import with UTF-8/UTF-16 and explicit GB18030; danmaku and native settings; native tracks/preferences, diagnostics, PiP/AirPlay/background; manual provider segments; user markers with opt-in automatic skipping; AList/OpenList and read-only WebDAV; manual LAN DLNA controls; Files-provider SMB staging; bounded foreground offline files | Styled ASS/fonts/karaoke, subtitle matching/auth variants, automatic provider skipping/detection, production SSDP entitlement/discovery/device list, direct SMB browsing/streaming, authenticated/background/resumable/HLS offline media, cloud login, transcoding and physical acceptance #5/#38/#114 |
| P5 | Accounts, pairing/revocation, hashed device credentials, CAS library sync, authenticated WebSocket remote control, bounded DNS-pinned HTTP/HLS relay, provider health/search cache, EPG scheduling, H2/PostgreSQL/NAS restart/restore | Actual remote-NAS operational/security/load acceptance #6 |
| P6 | Web audit/CycloneDX, immutable image/Action pins, strict JVM locks/SHA-256 verification and rejection probes, shipped API-library SBOM, unsigned Web/API/Linux amd64 candidate packaging with source/checksums and host/Docker JAR equality; JVM maintenance refresh in #93 | Independent JVM/container/license/provenance review, complete runtime/container SBOM, performance budgets, rollback drills, ARM/native artifacts and signed Apple distribution #7 |

## Native provider skip implementation increment

Merged PR #175 adds bounded FongMi `Result.skips` normalization and explicit native manual seeking through the existing player. Opening/middle/ending hints retain millisecond timestamps and nullable ending-to-EOF semantics. Generation/URL/range validation excludes stale, local, replay and known timeshift contexts; hints remain ephemeral and do not alter saved user markers. The exact source-head evidence above accepts this implementation increment and closes #174. See [IOS_PROVIDER_SKIPS.md](IOS_PROVIDER_SKIPS.md). Automatic provider skipping, Web controls and the broader P2/P4 backlog remain open.

## Native delivery boundaries

- **DLNA:** explicit private-LAN AVTransport URL or same-origin UPnP description import; optional name/model/UDN and DIDL-Lite title; SetURI/play/pause/resume/stop, fresh state/position, relative and absolute finite-media seek. Media/renderer edits, navigation and failed commands invalidate stale controls. Current-media autofill excludes local/replay/header-protected inputs. See [IOS_DLNA.md](IOS_DLNA.md).
- **SSDP:** parser, fixed-target bounded UDP transport and candidate-to-description/UDN resolver are implemented and owned-fixture tested. Production UI remains manual. Apple multicast entitlement/provisioning, a production discovery list and real LAN iPhone/iPad/TV acceptance remain #114. See [IOS_SSDP_DISCOVERY.md](IOS_SSDP_DISCOVERY.md).
- **SMB:** imports user-selected documents from an SMB share already connected in Apple's Files app. Coordinated staged copying has cancellation/progress, size/free-space checks and abandoned-cache cleanup. It is not a native SMB directory client or direct streaming. See [IOS_SMB_FILES.md](IOS_SMB_FILES.md).
- **Offline media:** foreground, Wi-Fi, direct unauthenticated file downloads; 512 MiB per file, 2 GiB total, 20 completed copies, manifest persistence and explicit deletion. HLS/DRM/background/resume/authenticated downloads are not implemented. See [IOS_OFFLINE_MEDIA.md](IOS_OFFLINE_MEDIA.md).
- **Captions/tracks:** four overlapping text cues with bounded display, explicit legacy encoding and independent embedded/HLS AVPlayer track selection. Full unique track identity is required for saved choices; invalid/ambiguous choices do not restore stale preferences, and each title can forget audio/subtitle preferences. Rich ASS and external overlays in PiP are not implemented.

## Source and execution evidence

Use [UPSTREAM_COMPATIBILITY.md](UPSTREAM_COMPATIBILITY.md), [LIVE_REPLAY.md](LIVE_REPLAY.md) and [PURE_JVM_SPIDER.md](PURE_JVM_SPIDER.md) for exact pinned FongMi classes/signatures and supported subsets. The supplied subscription envelope loaded 49 type-3 sites in the earlier recorded check; this is a historical parse result, not a current availability or playback guarantee. Its DEX/ARM-native package cannot run through the pure-JVM loader. The Android bridge still requires an actual separate ARM Android host and representative execution evidence.

P1 implementation is closed independently of physical acceptance. P2–P6 remain open. No signed IPA, TestFlight or published Release is established by these checks. Remaining code can continue while device/corpus/review/signing resources are handled separately.

## Historical implementation notes

The dated slices below preserve previous design and test context. Statements such as “pending gate”, “not implemented” or “current PR” describe that historical slice; the current inventory above and its linked source are authoritative for planning. Exact historical run links remain evidence for their original commits only.

## Native WebDAV RFC 4918 propstat/href parsing (P4, #72)

The native Depth:1 parser now treats only direct DAV:response/DAV:href as resource identity and requires a 2xx DAV:propstat/DAV:resourcetype to list a file or folder. Collection flags from failed properties, nested/foreign XML and failed response statuses cannot misclassify or inject listings. Synthetic positive/negative Swift smoke, XCTest and localhost PROPFIND fixtures exercise the contract; final-head aggregate CI and physical/provider verification remain separate. This is not a new network transport, SMB/DLNA implementation or security audit.

## Native WebDAV incremental response cap (P4)

The native WebDAV `PROPFIND` transport now rejects oversized declared responses and reads unknown-length XML bodies incrementally, aborting after 1 MiB instead of allocating the entire body through `URLSession.data(for:)`. A localhost fixture tests both size cases, a successful listing after rejection, existing redirect/auth policy and bounded parser behavior. See [IOS_WEBDAV.md](IOS_WEBDAV.md) and issue #70. This is not a full network resource quota, physical-device acceptance, or independent security audit. Final-head CI evidence belongs to the associated PR.

## Native read-only WebDAV increment (P4)

A dedicated SwiftUI WebDAV browser provides bounded RFC 4918 Depth:1 listings and optional HTTPS Basic credentials held in view memory. Only same-origin immediate descendants under the configured root are displayed; unsafe XML, cross-origin paths and redirects are rejected. Media selection reuses AVPlayer and the existing authenticated capability relay for header-protected resources. See [IOS_WEBDAV.md](IOS_WEBDAV.md). Positive/negative Swift smoke tests, iPhone/iPad XCTest/XCUI and final-head integration CI are required before closing #66. No SMB, real-device/provider or security-audit acceptance is claimed.

## Native manual intro/outro markers (P4, PR #69)

Explicit per-title SwiftUI intro-end/outro-start markers now drive bounded AVPlayer seeking without automatic detection. Only ready finite remote VOD is eligible; URL digests and duration-matched numeric markers are stored locally (100 records/64 KiB), with invalid snapshots ignored and clear-library cleanup. Standalone Swift smoke passed locally; final-head iPhone/iPad XCTest/XCUI and aggregate CI are required before merging. No physical-device, provider-supplied chapter, automatic skip, or release claim. See [IOS_INTRO_OUTRO.md](IOS_INTRO_OUTRO.md).

## Native inline seeking increment (P4)

The SwiftUI iPhone/iPad player now exposes explicit 15-second backward and
forward actions using the already validated finite-VOD remote-command seek
path. This adds no new network transport or persisted state. XCTest covers
successful forward/backward seeks clamped to media bounds and existing
negative inputs; XCUI checks both production controls are disabled with no
media. This does **not** implement automatic intro/outro detection or claim
physical-device playback. Final-head simulator and full integration CI are
required before merging this slice.

## Native audio identity collision regression (P4)

The original per-title audio preference code shortened track names to 80 characters before persistence and compared shortened names on restoration. This could restore the wrong rendition when a provider changed tracks or shared a long prefix. The current PR uses full AVFoundation name/language identity, refuses to persist names longer than 80 characters, migrates v1 snapshots conservatively (dropping ambiguous 80-character entries), removes a stale preference after an unpersistable explicit choice, and requires a unique exact match. XCTest covers matching and collision/failure cases; the existing synthetic HLS playback tests continue to exercise the real player selection path. This is not real-device or third-party provider verification. Final-head CI evidence belongs to the PR.

## Live replay increment

See [LIVE_REPLAY.md](LIVE_REPLAY.md). Reference: original **FongMi/TV `123cc086159b0f13bf54bdf64bacbc259ca47c88`**, `Timeshift`, `TimeshiftPlayback`, `Catchup`, `Channel`, `LiveParser`.

- Timeshift uses Unix milliseconds, the explicit provider window and a zero live sentinel; its URL returns Result JSON, not video. Programme catchup is a separate bounded start/end path.
- Both clients have explicit time selection, return-to-live, cancellation and error feedback; XMLTV adds up to 40 historical programmes/channel. Failed resolution retains current playback.
- Authorization precedes provider I/O. DNS-pinned text/media transports, credential scope and relay quotas/revocation are reused. Private provider URLs/headers are not returned in the replay response.
- Replay templates/capabilities and replay progress are excluded from persisted/synced libraries. Clients must reload subscriptions after restart to restore replay metadata.
- Shared Kotlin/Swift/Vitest golden fixtures, MockMvc authorization/revocation, native snapshot/player tests and browser regression supplement the existing full gate. Automated fixture success does not establish licensed real-provider or physical-device acceptance.

Do not close parent P2/P3/P4/P5/P6 issues from this subset. No signed Release/IPA/TestFlight package has been published. Human/resource gates remain: physical devices, permitted external plugin/provider corpus, independent security assessment and Apple distribution credentials/release decision.

## Real subscription / Android runtime increment

See [REAL_SPIDER_COMPATIBILITY.md](REAL_SPIDER_COMPATIBILITY.md) and
[ANDROID_SPIDER_BRIDGE.md](ANDROID_SPIDER_BRIDGE.md). The user-provided IDN URL's
image/Base64/comment envelope loads through the built API (49 type-3 sites).
Its referenced package contains DEX and ARM native guards, not JVM classes.
The optional bridge delegates approved init bindings to an existing separate
FongMi Android host; authentication, polling, deadlines, cleanup and opaque-ID
contracts have automated tests. No ARM host is available here, so this does not
claim actual Spider execution, complete P3 compatibility or release acceptance.

## Native WebDAV completion-status CI regression (#74)

The 2026-10-29 main push full gate [40809764313](https://github.com/Kahen/TV-Next/actions/runs/40809764313) failed in the iPad-only localhost WebDAV network smoke with `invalidResponse`, despite the iPhone and other jobs succeeding. This follow-up adds a final-task-response HTTP status/length fallback, explicit EOF for unknown-length localhost fixtures, and positive/negative/size-boundary transport regressions. It does not weaken redirect rejection, byte caps or credential handling, and it is not evidence of real-device/provider acceptance. Final-head iPhone/iPad and aggregate CI must succeed before merging this slice.

## Native WebDAV local browse controls (P4, #76)

The SwiftUI WebDAV view adds explicit current-folder refresh and device-local filename/media-only filtering over the previously bounded Depth:1 listing. The filter never changes server requests, URL paths, headers or credentials; folders remain navigable in media-only mode, and the first-200-entry cap still applies. Refresh preserves the last successful listing on failure and rejects stale asynchronous responses through the existing request generation guard. Swift smoke, XCTest and production XCUI against the owned localhost PROPFIND fixture cover positive/negative UI, filtering, refresh and disconnect behavior; final-head full CI and physical/provider acceptance remain separate.

## Native WebDAV bounded breadcrumb navigation (P4, #78)

Native SwiftUI adds direct root/ancestor shortcuts for nested WebDAV folders. A pure Swift helper derives at most 32 canonical directory ancestors from already root-validated URLs, rejecting foreign origins, sibling roots, non-directory inputs and over-depth paths. The UI invokes the existing bounded/cancelable directory fetch, not a new transport. Swift smoke, XCTest and iPhone/iPad XCUI against the owned localhost nested-folder fixture provide positive/negative regression coverage. Final-head aggregate CI and physical-provider validation remain distinct.

## Native offline deletion confirmation (P4, #83)

Offline copies now require an explicit destructive confirmation before deletion.
Cancel preserves the file, catalog entry and any active AVPlayer item; confirm
releases only the matching local player item and removes the copy. The native
section displays the current count and byte usage against the existing quota.
Production iPhone/iPad XCUI covers owned-fixture download, relaunch, playback,
cancel and confirm. See [IOS_OFFLINE_DELETE.md](IOS_OFFLINE_DELETE.md).
Final-head simulator/integration gates and physical-device acceptance are distinct;
this does not implement resumable/HLS/DRM downloads, SMB/DLNA or signed releases.

## Native WebDAV folder-first sorting (P4, #96)

The native connected-directory view now offers a local ascending/descending natural filename sort. Folders remain first; a deterministic URL tie-breaker avoids unstable equal-name ordering. The selected order survives directory navigation and refresh but resets on new connection/disconnect. This does not change Depth:1 requests, the 200-entry limit, credential handling or media relay. Positive/negative/boundary Swift smoke and XCTest plus production SwiftUI XCUI are added; final-head CI, physical-device and external-provider verification are separate. Parent P4 #5 remains open.

## Native WebDAV bounded file sizes (P4, #98)

Read-only native WebDAV requests optional `DAV:getcontentlength` in the same Depth:1 listing, displays validated file byte counts and omits unknown/folder sizes. Successful direct DAV propstat scope and 0–8 TiB decimal bounds prevent malformed/foreign/failed metadata from being shown. No extra network request, credential persistence, server-side sort, SMB/DLNA or device acceptance is implied. Final-head Swift smoke/XCTest/XCUI and full integration evidence belong to issue #98; parent #5 stays open.


## Native manual DLNA AVTransport subset (P4, #100)

Native SwiftUI now exposes a manually entered LAN AVTransport control URL and direct HTTP(S) media URL. A bounded SOAP v1 client issues SetAVTransportURI → Play, and separate Pause/Stop, following FongMi's mobile DLNACast sequence. Renderer endpoints are restricted to explicit private/loopback IPv4 HTTP literals; redirects, credentialed URLs and oversized/malformed SOAP responses are rejected. A synthetic localhost fixture and iPhone/iPad XCTest/XCUI cover positive/negative paths; **final-head CI is required before accepting this increment**. This is not SSDP discovery, real renderer/codec interoperability, credentialed media relay, signed distribution or physical-device acceptance. See [IOS_DLNA.md](IOS_DLNA.md). P4 #5 remains open.

## Native DLNA read-only transport status (P4, #102)

A native iPhone/iPad manual renderer now supports explicit AVTransport v1 GetTransportInfo and a read-only status button, reusing the bounded SOAP transport. The parser requires one direct CurrentTransportState in the correct SOAP action response and accepts only known UPnP state values; invalid/nested/duplicate/foreign values fail closed. A stateful owned fixture, positive/negative Swift smoke, XCTest and production XCUI test the reported transitions. Final-head CI evidence belongs to the feature PR. This is not SSDP discovery, a physical TV compatibility result, a decoder test or a security audit.


## Native DLNA read-only position snapshot (P4, #104)

The native manual DLNA view adds an explicit GetPositionInfo request and a strict bounded SOAP RelTime/TrackDuration parser. No automatic polling, seek, persistence, SSDP or extra destination is introduced. Positive/negative Swift smoke, owned loopback transport, Python fixture and production iPhone/iPad XCUI are part of the new slice; only final-head successful CI constitutes automated acceptance. Real TV/Apple hardware and signed release remain unverified; parent #5 stays open.

## 2026-10-30 native manual DLNA bounded seek (#106)

A new iPhone/iPad explicit ±15-second REL_TIME seek subset uses fresh AVTransport GetTransportInfo/GetPositionInfo and strict finite-duration clamping before a private-LAN SOAP Seek. The owned fixture and positive/negative Swift/Python/XCTest/XCUI regressions are tracked in the feature PR; only a successful final-head full gate permits merging/closing the implementation issue. SSDP, real renderer models, SMB, independent security review, physical Apple devices and signed distribution remain unverified. P4 #5 and P2–P6 remain open.

## Native DLNA explicit pause/resume control (P4, #108)

A native SwiftUI **继续播放** button is enabled only after an acknowledged pause or a fresh user-requested PAUSED_PLAYBACK state. A second fresh GetTransportInfo immediately precedes Play(Speed=1), rejecting stopped, already-playing and unsupported states. Renderer/media edits and failures clear the local paused state. The owned loopback SOAP fixture is exercised by positive/negative Swift network smoke, XCTest and production iPhone/iPad XCUI. This is pending final-HEAD integration CI, and does not establish actual TV/Apple device support, SSDP, SMB or release readiness.


## Native DLNA absolute time seek (P4, #110)

A native SwiftUI HH:MM:SS field and explicit seek action extend the manually configured private-LAN AVTransport subset. Input is strictly ASCII and validated before network access; the action checks fresh renderer state and finite media duration and rejects targets beyond the reported duration. Owned fixture, positive/negative Swift smoke/XCTest, network and production iPhone/iPad XCUI are part of the PR; final-head full CI remains required. No SSDP, real renderer compatibility, SMB, physical device acceptance or signed distribution is implied.

## Native opt-in DLNA device-description import (P4, #112)

The manual iOS DLNA page now accepts an explicitly supplied private-LAN UPnP device-description URL and imports its unique, same-origin AVTransport:1 control endpoint after a bounded GET and strict XML validation. No SSDP, multicast discovery, automatic playback, credentials, URLBase trust or additional server endpoint. Positive/negative Swift smoke, localhost network, XCTest, production SwiftUI XCUI and final-head CI are required before implementation acceptance. Real TV/iPhone/iPad, broader UPnP compatibility, SMB, independent security review and signing are not claimed.

## Native SSDP response parser prerequisite (P4, #114)

A pure Swift, non-networking parser now screens bounded SSDP M-SEARCH HTTPU response datagrams and sender-matched private IPv4 LOCATION candidates before any future UPnP device-description fetch. Adversarial Swift smoke/XCTest cases cover forged origin, duplicate headers, unsupported targets, malformed line endings, trailing bodies and size limits. This is not a multicast implementation or a user-visible discovery feature. Final-head iPhone/iPad simulator and aggregate CI must pass before accepting the parser increment. SSDP M-SEARCH transport, Apple multicast entitlement/provisioning, actual iPhone/iPad and renderer tests remain open under #114 and parent #5.

## Native optional UPnP renderer friendlyName (P4, #116)

An explicit native DLNA device-description import now returns a bounded, display-only friendly name alongside the previously validated same-origin AVTransport control URL. Names are optional, not trusted as device identity, and neither persisted nor used as authorization. Malformed/duplicate/nested/foreign/oversized/control/bidi names are rejected; owned Swift smoke/XCTest/XCUI and loopback fixtures are required, with final-head full CI before merging. SSDP transport/entitlement, real renderer interoperability, SMB, Apple hardware acceptance and P6 release remain open.

## Native WebDAV bounded last-modified display (P4, #119)

The iPhone/iPad read-only Depth:1 PROPFIND now requests optional `DAV:getlastmodified` and displays validated RFC 1123 GMT timestamps in the SwiftUI listing. The parser accepts only direct DAV properties in successful propstat; duplicate, conflicting, nested, foreign, failed, malformed and oversized values become unknown rather than blocking file access. The existing 1 MiB XML, 200-entry, credential-scope and no-redirect limits remain unchanged. Owned fixture, Swift positive/negative smoke, network, XCTest and iPhone/iPad XCUI are part of the PR; final-head aggregate CI must pass before merge. No external provider, physical Apple device, SMB, independent security audit or release validation is claimed.

## Native UPnP optional renderer modelName (P4, #118)

The explicit, user-entered LAN description import parses one bounded optional direct `root/device/modelName` and displays it in native SwiftUI beside the approved control URL and optional friendly name. Empty/missing is valid; duplicate, nested, foreign, control/bidi or oversized model names fail closed. Model data is display-only and never persisted or used for endpoint trust. Owned Python loopback, Swift parser/network smoke, XCTest and production iPhone/iPad XCUI are required; final-head full CI is pending before merge. This does not establish SSDP multicast discovery, SMB, physical Apple/TV interoperability, legal Spider corpus, independent security audit or signed release.


## Native opt-in DLNA DIDL-Lite metadata (P4, #122)

This PR adds a user-entered optional title to native manual casting. Empty title preserves the existing empty CurrentURIMetaData; a bounded, validated title generates a FongMi-inspired DIDL-Lite videoItem with the same direct media URL and generic video protocolInfo. It does not serialize provider headers, persist the title, or add any network destination. Positive/negative Swift smoke, owned localhost SOAP fixture and production iPhone/iPad XCTest/XCUI are required, followed by final-head aggregate CI. Physical TV/Apple device compatibility, SSDP entitlement, SMB, security audit and signed release remain unverified.


### Native Files-provider SMB import (#124; pending final HEAD gate)

The existing Files document picker gains an explicit SMB-share entry and the local-media staging path gains NSFileCoordinator, cancellation propagation, bounded 1 MiB streaming, actual 2 GiB enforcement and partial-copy cleanup. This only imports files selected from an SMB share already connected through Apple's Files app; it does not implement native SMB directory browsing or direct remote playback. Synthetic tests and final-head iPhone/iPad CI must pass before merging; physical NAS/Apple devices remain unverified. Parent P4 #5 remains open.


#### 2026-11-01 Files picker presentation follow-up (#124)

The earlier local-section `fileImporter` relocation did not fix iPhone/iPad XCUI: full CI [41231112970](https://github.com/Kahen/TV-Next/actions/runs/41231112970) still failed 2 simulator jobs while Web/API and six other integration jobs passed. The media picker now uses an explicit SwiftUI sheet containing Apple's `UIDocumentPickerViewController`, with app-owned cancellation controls and unchanged security-scoped bounded staging. XCUI checks sheet presentation/dismissal and preservation of the unplayed state. It does not certify Files provider browsing, actual SMB hydration or NAS compatibility. Final-HEAD aggregate CI is required before #124 closes.

## Native Files/SMB cancelable media staging (#126)

Following the Files-provider bounded import in #125, the native SwiftUI view exposes copied-byte progress and an explicit cancel action while an import is active. The detached coordinated read receives cancellation through its parent Task, and generation checks prevent late callbacks or successful-but-cancelled copies from triggering playback. Synthetic Swift smoke/XCTest cover positive progress, preflight and mid-copy cancellation and partial-file cleanup; production XCUI covers the no-import state after picker dismissal. Final-head simulator/aggregate CI is required. This does not establish actual NAS SMB interoperability, immediate interruption of NSFileCoordinator, physical-device compatibility, independent security review or signed distribution.


## Native Files/SMB cold-start cache reclamation (#128)

User-selected Files documents are staged into a private app cache and never persisted as resumable media. After an unexpected process exit, a prior staged file could remain. App initialization now removes only UUID-named, supported-extension regular files from that dedicated directory; it excludes other files, directories, symlinks and redirected cache roots, and never runs during an active session. Synthetic positive/negative Swift smoke and XCTest cover the cleanup contract. Final-head CI and actual iPhone/iPad/NAS validation remain separate; this is not native SMB directory access, streaming or signed distribution.


## Native Files/SMB storage preflight (P4, #130)

The iOS staged-copy path now checks the cache volume's reported free capacity before allocating a local media copy, reserving 64 MiB after any known source length. Unknown File Provider lengths require the reserve only; missing capacity metadata does not block an otherwise permitted import. Out-of-space errors during actual writes map to a localized storage warning, while partial copies are removed. Swift smoke/XCTest cover exact boundaries, large values and error mapping. This is a conservative preflight, not a guaranteed space reservation or real iPhone/NAS validation; final-head simulator and aggregate CI are required.


### P4 iOS SSDP UDP M-SEARCH transport (#132)

The new NativeSSDPDiscovery actor provides a dormant opt-in fixed-multicast M-SEARCH implementation with two bounded targets, TTL 1, a 3-second deadline, cancellation, a 10-second cooldown, 64-packet/4096-byte receive bounds and 32 deduplicated candidate locations. It reuses the existing strict private IPv4 sender-matched response parser. A DEBUG-only owned loopback UDP fixture tests transport behavior. The production SwiftUI DLNA page remains manual because Apple multicast entitlement, signed profile and real iPhone/iPad permission are **not** established. Final-head simulator and full CI are required for subtask closure; parent #114 remains open. See [IOS_SSDP_DISCOVERY.md](IOS_SSDP_DISCOVERY.md).

## Native Files/SMB caption reader (#134, 2026-11-01)

The native external subtitle picker now delegates to a detached, cancellable, security-scoped and NSFileCoordinator-backed SRT/VTT/ASS/SSA reader. It enforces a 1 MiB actual byte cap even when a provider's size is stale, preserves prior cues on failure/cancel, and prevents stale completion after playback/library changes. Swift smoke/XCTest, native XCUI and aggregate CI must pass on the final PR HEAD before merging. This does not implement direct SMB browsing/streaming, styled ASS, real NAS interoperability, independent security audit or signed distribution. See [IOS_CAPTION_FILES.md](IOS_CAPTION_FILES.md).

## Native Files subtitle UTF-16 increment (#136, 2026-11-01)

Adds explicitly BOM-marked UTF-16LE/BE subtitle text decoding to the existing native Files/SMB SRT/VTT/ASS/SSA path; UTF-8 behavior, 1 MiB raw-byte cap, cancellable coordinated reads and text-only parsing remain unchanged. Invalid BOM-only, odd-length and unpaired-surrogate sequences are rejected. Swift smoke/XCTest and final-head iPhone/iPad/full integration results must be attached to PR #137 before the subtask is closed. Legacy GBK/GB18030 and real NAS/iPhone/iPad remain unverified; P4/P6 parents stay open.

### P4 iOS root-device UDN identity binding (#138, 2026-11-01)

Manual native UPnP device-description import now parses and displays an optional bounded `uuid:` root UDN. A pure discovery-candidate validation helper binds the SSDP USN UUID to that UDN and rejects missing/mismatched identity while retaining strict same-IP/port AVTransport control URL validation. Manual imports without UDN remain compatible. Positive/negative Swift smoke, XCTest, owned localhost XML and iPhone/iPad XCUI plus final-head integration are required for this subtask. Apple multicast entitlement, real renderer/iPhone/iPad interoperability, authentication of the device identity and parent #114/#5 remain open.


## Native SSDP candidate-to-description resolution (P4, #140)

A dormant Swift resolver now preflights previously parsed SSDP candidates before requesting any LOCATION, then uses the existing bounded private-LAN UPnP GET and checks root-device UDN against SSDP USN and AVTransport control origin. Owned positive/negative smoke and XCTest cover unsafe metadata, mismatched identity/control origin, and cancellation. This is not a user-facing multicast scanner, cryptographic device authentication, automatic casting or proof of physical interoperability. Final HEAD `b5244f37` passed [Web/API](https://github.com/Kahen/TV-Next/actions/runs/41317811679) and [full integration](https://github.com/Kahen/TV-Next/actions/runs/41317811712), including iPhone/iPad XCTest/XCUI; PR #141 merged and #140 closed. #114 and P4 #5 remain open. No Apple signing or Release.


## P4 native iOS explicit GB18030 subtitle import (#142)

The user may explicitly select GB18030 for a **local Files/SMB SRT/VTT/ASS/SSA** import. Default decoding remains strict UTF-8 or BOM-marked UTF-16LE/BE; no legacy encoding sniffing or persisted charset is added. The choice is captured when import starts, while the existing coordinated 1 MiB read, cancellation, old-cue-on-error behavior and private Files Provider credentials remain unchanged. Malformed GB18030 and BOM-marked input in legacy mode are rejected. Remote subscription captions are unaffected. Swift smoke, XCTest and production iPhone/iPad XCUI plus final-HEAD Web/API and full integration CI are required; physical SMB/provider behavior, Apple signing and P4 parent #5 remain unverified.


## Native P2 cross-site failed-provider retry (#144, 2026-11-02)

The existing bounded SwiftUI FongMi type 0/1/2/4 cross-provider search now exposes a retry control only after partial provider failure. It uses stable site keys rather than potentially duplicated display names, captures the original submitted keyword, requests failed providers only, and merges recovered hits into original site order without replacing successful results. A repeat failure retains previous partial hits; stale/cancelled generation callbacks remain excluded. The original 16-site / 4-concurrent / 2-page / 600-hit limits remain. The owned localhost API fixture deliberately fails the first B search and rejects A refetch or a changed retry query. Swift smoke, XCTest and production iPhone/iPad XCUI plus final-head aggregate CI are required before closing #144. Parent P2 #3, real-provider corpus, physical Apple-device testing, Spider security and signing remain open. See [IOS_CROSS_SITE_RETRY.md](IOS_CROSS_SITE_RETRY.md).

## Native cross-site search provenance correction (P2, #146)

The existing failed-only retry routes by eligible provider keys, but its result buttons previously looked up a display name in the unfiltered subscription. A hidden/unsupported earlier duplicate key could therefore mislabel a real searched provider. Native SwiftUI now stores a nonpersistent selected-provider name snapshot alongside the original search ordering and clears both on context reset. The shared helper enforces first eligible key and 16-site cap. Synthetic Swift smoke/XCTest and production iPhone/iPad XCUI with an owned hidden-duplicate fixture provide regression coverage; final-head CI must pass before merging. This does not validate real FongMi providers, Apple hardware, Spider safety or release readiness.


## Native P2 cross-site completed-empty feedback (#148)

A completed native SwiftUI cross-provider search with no visible hits no longer looks like an untouched search form. The display differentiates zero-match success, partial failure and all-failed outcomes, with the same existing failed-only retry. The completion flag resets on new searches, subscription/context changes and view dismissal, and updates only after the current-generation search or retry finishes. Pure Swift positive/negative/boundary tests, a localhost empty-result fixture, Python tests and production iPhone/iPad XCUI are added. Final HEAD aggregate CI is required before closing this implementation issue. P2 #3, real-device/provider, P3 legal/sandbox review and signed release remain open.

## Native subtitle preference stale-choice eviction (P4, #150)

When an explicit embedded/HLS subtitle choice cannot be represented as a complete saved name/language identity, native iOS now clears the prior per-title preference instead of retaining a stale track/Off choice for the next playback. Current AVPlayer track selection is unchanged. Valid choices and supported Off remain stored only as bounded SHA-256-keyed local metadata. Pure Swift policy smoke and owned HLS XCTest cover valid/invalid and 80/81, 64/65 boundaries; final-head iPhone/iPad and aggregate CI must pass before merging. No physical-device/provider, Spider compatibility, audit or Apple signing claim.

### Native audio/subtitle hidden-option identity collision (#152, 2026-11-02)

AVFoundation may report more than the 16 tracks exposed in the native menu. Previously an invisible duplicate could make a saved visible audio/subtitle name-language identity ambiguous while the restore logic still selected it. The new Foundation-only policy scans the entire option group, restoring only a unique exact identity within the 16 visible choices; later duplicates and unique hidden-only choices leave the system selection untouched. Positive/negative/16–17 boundary Swift smoke, XCTest for both track kinds, final-head iPhone/iPad unsigned simulator build/XCTest/XCUI and Web/API/PostgreSQL/Compose/NAS/Spider isolation are required before merging #152. This does not establish physical media compatibility, external-provider parity, security audit or signed distribution. Parent P4 #5 remains open.

### Native per-title track preference forget controls (P4, #154, 2026-11-02)

Native SwiftUI audio and embedded-subtitle menus now expose a future-playback-only forget action for a remembered current remote title. Only the matching SHA-256 URL-digest record is removed from the bounded UserDefaults snapshot. The current AVPlayer selection, subtitle Off state, playback position and unrelated title/type preferences are not modified; local/replay/no-preference contexts are no-ops. Owned HLS XCTest and iPhone/iPad production XCUI plus final-head aggregate CI are required before merging. This does not close P4 #5 or claim real-device/provider, independent audit, Spider legality corpus, signing or release acceptance.

## Native cross-site oversized-page warning (P2, #156)

Native iOS now reports when a provider returns more than the allowed 40 entries in a single response, even if it sets `hasMore=false`. This warning is independent of the existing second-page `hasMore` warning. Results stay capped and provider-scoped, and failed second pages preserve clipping visibility without leaking upstream errors. Swift positive/negative/boundary smoke, XCTest, owned Python fixture and production SwiftUI XCUI cover this implementation slice; final-head full integration and real-device/provider acceptance remain separate. Parent P2 #3 stays open.


## Native cross-site retry warning reconciliation (P2, #158)

The original retry UI appended warning strings, so a recovered provider could leave obsolete clipping/page-limit warnings after its partial results were replaced. Structured per-provider-key warning provenance now follows the same recovered-only replacement policy as search results. Failed-again providers retain their previous warning state; healthy providers and the initial site cap are untouched. The global 600-result warning remains conservatively sticky after retry because discarded overflow cannot be recomputed without re-fetching healthy sites. Owned Swift, Python and iPhone/iPad XCUI regressions require final-HEAD aggregate CI before merge. Parent P2 #3, external provider/device acceptance and P3/P6 gates remain open.

## Native manual DLNA read-only failure control-state regression (P4, #160)

A failed GetTransportInfo/GetPositionInfo does not prove the last acknowledged cast stopped. Preserve Stop/Pause availability for an acknowledged cast, but invalidate paused/Resume until a new verified state; mutating-command errors still fail closed. Owned Python SOAP fixture, Swift smoke/XCTest and production iPhone/iPad XCUI are required at the final PR HEAD. See [IOS_DLNA.md](IOS_DLNA.md). Physical iPhone/iPad/TV, multicast entitlement and release/security acceptance remain open.

## P4 native manual DLNA navigation-state invalidation (#164, 2026-11-02)

Leaving the native DLNA screen cancels any in-flight request and discards UI-only cast/paused flags, stale status/error and previous seek text. Renderer/media fields are not persisted or sent to a server, and navigation never sends an implicit Stop to the renderer. A fresh explicit cast or verified transport-state query is required to enable playback controls after return. This differs from a failed read-only query **within** the same screen, which preserves the last acknowledged cast. Swift smoke/XCTest and production SwiftUI iPhone/iPad XCUI use only the owned localhost fixture; final-head Web/API, PostgreSQL, Compose, NAS, Spider isolation and aggregate CI are required before merging. Physical Apple/TV interoperability, multicast entitlement, legal Spider corpus, security audit and signing remain open.

## Native DLNA failed Seek control invalidation (P4, #162)

A rejected relative or absolute Seek no longer leaves previously acknowledged Pause/Stop/Resume UI controls enabled. Both SwiftUI paths reuse the mutating-command fail-closed policy, preserve entered endpoints and surface the error. Owned Python SOAP fixture, Swift smoke/XCTest and production iPhone/iPad XCUI are required with the final-HEAD Web/API/PostgreSQL/Compose/NAS/Spider aggregate gate. This is not physical TV/Apple compatibility, multicast permission, Spider authorization, security audit or signed release evidence. See [IOS_DLNA.md](IOS_DLNA.md).

The native root uses one persistent `ScrollViewReader`/`VStack`: toolbar section changes scroll without necessarily firing the DLNA subview's `onDisappear`. The implementation therefore observes explicit navigation requests as well as actual disappearance; reselecting DLNA does not reset an active session. The iPhone/iPad XCUI regression covers both paths.

## Native iOS DLNA current-media autofill eligibility (P4, #166)

The “使用当前播放地址” control now uses the same bounded direct HTTP(S) media-URL validator as the actual DLNA cast path for both enablement and tap handling. Empty, file/local, credentialed, malformed/oversized, custom-header and replay media cannot silently enable a no-op autofill. A valid explicitly imported direct URL remains eligible. Foundation-only Swift positive/negative smoke and XCTest plus production SwiftUI iPhone/iPad XCUI against an owned M3U fixture cover the behavior. This is UI safety/feedback, not new renderer discovery, external-provider compatibility or physical TV acceptance; final-head full CI is required before merge.


### P2 native failed-only search boundary regression (#168)

The iOS retry coordinator now intersects failure keys with the original selected-site snapshot and the same first-16-unique eligible-provider boundary used by initial search. It does not expand requests to a 17th, newly inserted or otherwise unsearched provider. Swift smoke/XCTest cover negative and positive cases, including actual request counts; existing iPhone/iPad XCUI and full integration CI must pass on the final PR HEAD before closing #168. Physical devices, permitted external providers and P2/P3/P6 acceptance remain separate.

### 2026-11-09 — PR #188 provider-skip consent follow-up

- Final-head CI on `22281d46` failed iPhone/iPad `testProviderAutomaticSkipRequiresExplicitToggleAndResetsForNextEpisode` at the post-tap accessibility value assertion; this is not a passing simulator gate. The existing test covers opt-in, feedback and same-URL next-episode reset; no assertions were removed.
- Updated `NativeProviderSkipControls` to read `library.playbackGeneration` when the Toggle binding setter runs rather than capturing a generation from a prior SwiftUI render. This addresses a possible stale-generation consent rejection; the exact root cause and effectiveness require simulator verification.
- Compose failed during locked Kotlin compiler download (HTTP 504) before browser tests; rerun required. Do not merge until the new HEAD passes iPhone/iPad, Compose and aggregate gate.

### 2026-11-10 — PR #188 consent interaction diagnosis (pending CI)

The final `098cb400` gate [#42801835526](https://github.com/Kahen/TV-Next/actions/runs/42801835526) still failed iPhone/iPad XCUI on the native automatic-provider-skip switch after a synthesized tap; unsigned builds, native smoke, and non-iOS jobs passed. This does not establish whether the Binding setter ran. The new branch commits `eb503cd1` and `28dd26f8` expose a user-facing, playback-local consent result or rejection message (`provider-skip-consent-status`) and retain the original switch-value assertion, with a diagnostic log of whether the result appeared. This is instrumentation and failure feedback, **not** a confirmed fix. Re-run the final HEAD iPhone/iPad simulator UI suite, negative consent/reset tests, and the full integration gate before merge. Physical iPhone/iPad acceptance remains #38. No third-party Spider execution or signed release is implied.

### 2026-11-11 — PR #188 native switch interaction

[Gate #42838355433](https://github.com/Kahen/TV-Next/actions/runs/42838355433) on `833fd8e4` passed all non-iOS jobs and 158 unit tests on each simulator. Both XCUI runs reported no consent result after tapping the labeled row. Each accessibility hierarchy exposed a distinct native switch inside that row. The updated test taps the child switch once and still asserts the row value, consent response and completed automatic seek. It then selects a distinct episode with the same URL and markers and checks that consent and feedback reset. The binding uses its playback generation so a stale control cannot grant consent to a newer playback. Final-head simulator and aggregate results are pending.


### 2026-11-14 — WebDAV external subtitles (pending final-head verification)

Native iPhone/iPad now offers explicit SRT/VTT/ASS/SSA selection from the connected WebDAV directory. Bounded device-local GET reuses the active account, rejects redirects, limits received bytes to 1 MiB, and supports Unicode plus explicit GB18030. New choices, disconnect and playback changes cancel stale loads; failures retain previous captions. The existing player offset/remove controls are reused. Request-policy XCTest, shared-loader race/error tests, real loopback HTTP smoke and production SwiftUI selection/failure/same-URL replay tests are included. Local Python fixture checks pass; final-head iPhone/iPad and full integration remain required. See [IOS_WEBDAV_CAPTIONS.md](IOS_WEBDAV_CAPTIONS.md). P4 #5 and physical acceptance #38 remain open.
