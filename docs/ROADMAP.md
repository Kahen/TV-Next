# TV-Next roadmap

Updated: 2026-11-04. Current code backlog: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). This is a delivery plan, not a claim that every feature exists.

## Goals and non-goals

Build independent Web/PWA and native iPhone/iPad clients with a shared, optional self-hosted service. Allow users to import authorized external media and FongMi-style configuration files. Do not bundle unauthorized streaming sources, DRM circumvention, site-specific bypasses, or remotely executable untrusted plugins in iOS.

Definition of done for each phase: implementation + automated checks + usage documentation + regression testing + explicit compatibility matrix. See docs/ACCEPTANCE.md for release gates. Each milestone may ship independently. Prioritize functioning vertical slices over superficial feature checklists.

## P0 — Foundations (initial implementation)

- [x] Initialize repository, development branch, docs and architecture
- [x] Web app shell, TypeScript types and basic player
- [x] Kotlin API with health and bounded M3U parsing/config inspection
- [x] SwiftUI iPhone/iPad app scaffold with native AVPlayer
- [x] Web/API CI and real Docker Compose build/boot/HTTP integration checks.
- [x] CI green on GitHub; unsigned native iOS simulator build passed on macOS (device test pending)

Acceptance: Web dev server works; API tests pass; import an explicitly provided M3U containing an HTTP(S) media URL; MP4/HLS playback works for compatible CORS-enabled sources; iOS can open user-supplied native-compatible media URL. No Spider execution yet.

## P1 — Media browsing and playback MVP

Tracking: https://github.com/Kahen/TV-Next/issues/2. Detailed implementation/automation map: [P1_IMPLEMENTATION.md](P1_IMPLEMENTATION.md).

- [x] Persistent playlists, favorites, history and bounded finite-VOD resume on Web/iOS; local files and private headers are excluded from persistence.
- [x] M3U/static JSON file and paste imports, groups/search, M3U export, validation and invalid-import recovery.
- [x] Local media inputs and external SRT/WebVTT text captions with timing offset.
- [x] Speed controls; browser fullscreen/PiP APIs with unsupported feedback; native fullscreen retaining caption/danmaku overlays, standard AVKit PiP on supported devices, and portrait/landscape layout.
- [x] PWA manifest/raster icons and shell-only offline cache; no offline streaming claim.
- [x] Keyboard/focus/active-view behavior on Web; labeled native controls, section navigation and large-text layout; lifecycle progress save and native background pause.
- [x] Owned MP4/HLS playback regression on Chromium/Firefox/WebKit; passing native XCTest and production SwiftUI XCUI workflows for both iPhone/iPad simulators.

Per explicit user instruction on 2026-10-25, close the implementation issue once code and automated acceptance pass; physical-device/installed-PWA acceptance is independently tracked in [#38](https://github.com/Kahen/TV-Next/issues/38). P1 basic system PiP is implemented; P4 adds opt-in background audio/system controls and AirPlay. Physical behavior remains separately tracked.

## P2 — FongMi core semantics

Tracking: https://github.com/Kahen/TV-Next/issues/3

- [x] Source-derived type 0/1/2/4 config decoding, sites/headers/ext/flags, depot selection and Web/iOS browsing.
- [x] Home/category/filter/search/detail/episodes/lines, native/Web bounded cross-provider search with cancellation and partial failure, and the documented HTTP action web workflow.
- [x] M3U/TXT/nested JSON live imports, offline and subscribed XMLTV/XMLTV.gz, persistent guide scheduling/cache and Web/iOS guide UI.
- [x] Explicit timeshift Result RPC, bounded programme catchup subset, historical XMLTV and Web/iOS replay controls; see LIVE_REPLAY.md.
- [x] Native AVPlayer embedded/HLS audio and subtitle selection menus with optional subtitle-off.
- [x] Native per-title audio/subtitle/off preferences with full unique identity, stale-choice eviction and per-title forget controls; opt-in subscription URL persistence in device-only Keychain.
- [x] Native failed-provider-only search retry with original query and provider provenance, completed-empty feedback and bounded-page clipping warnings.
- [ ] Broader audio/subtitle container and codec compatibility, including track identity changes across providers; device validation remains separate.
- [ ] Broader permitted real-provider corpus, interactive QR/login workflows, parser chains and long-tail replay formats; device validation remains separate.

Acceptance: comparison snapshots for home/category/detail/search/player APIs against a documented compatibility subset.

## P3 — Spider execution compatibility (highest risk)

Tracking: https://github.com/Kahen/TV-Next/issues/4

- [x] Explicit versioned contracts: v1 bundled-fixture RPC and v2 owned-JAR original Spider media signatures.
- [x] Bundled Java/Node/Python workers with fixed provider identities and Docker read-only/non-root/no-network/resource/output/time limits and cleanup regressions.
- [x] Bounded nonexecuting JAR/DEX/Android/JNI preflight and a separately compiled, hash-checked owned pure-JVM JAR loaded inside the OS sandbox (#85).
- [x] Administrator-bound Android SpiderTest bridge, five media operations, authenticated device binding and Web/native capability UI. This does not prove ARM plugin execution.
- [x] Bounded worker error codes, timeout/crash/output/resource rejection and supported-subset contract/isolation regressions.
- [ ] External pure-JVM artifact/dependency approval, permitted representative corpus and authorized dispatcher/API activation (#45).
- [ ] Real FongMi JS/QuickJS and Python adapters/dependency compatibility.
- [ ] Controlled egress, stateful Android sessions/actions/proxy callbacks and actual ARM DEX/native host validation.
- [ ] Independent host/isolation/security review and broader real-plugin compatibility corpus.

Acceptance: declared supported plugin fixtures pass on server; never execute remote code in the browser or iOS app. JVM bytecode alone is NOT a promise of Android JAR support.

### Approved owned-JAR contract slice

PR #85 adds an OS-isolated, version-2 harness which actually loads a separately
compiled, statically preflighted and SHA-256-checked owned JAR through the original
Spider media signatures. See [PURE_JVM_SPIDER.md](PURE_JVM_SPIDER.md). External
artifact/dependency approval, representative corpus, live host/API activation,
controlled egress, Android/DEX and real JS/Python compatibility remain pending.
This increment does not close P3.

## P4 — Advanced media features

Tracking: https://github.com/Kahen/TV-Next/issues/5

- [x] External SRT/WebVTT offsets, bounded ASS/SSA dialogue text and overlapping native text cues (#92), Web/native danmaku parsers and overlays.
- [x] Native PiP/AirPlay, audio/embedded subtitle selection and preferences, opt-in background audio and system media controls.
- [x] AList/OpenList browsing and bounded native read-only WebDAV with local filtering, refresh, parent/root breadcrumbs and credential revocation.
- [x] Native per-title manual intro/outro markers and explicit opt-in automatic skipping of those markers; no automatic detection/provider metadata claim.
- [x] Native foreground offline media-file downloads, persistent completed copies, local playback/deletion and byte/count quotas; see IOS_OFFLINE_MEDIA.md.
- [x] Native subscription external subtitle resources and stale subtitle/danmaku request invalidation; active WebDAV credentials remain fixed until reconnect (#89).
- [x] Read-only native codec/dimensions/audio/buffer/error diagnostics with credential redaction; actual hardware decoder selection is not exposed.
- [ ] Styled ASS/fonts/karaoke, advanced subtitle matching/headers and provider-supplied/automatic skip detection.
- [x] Manual private-LAN DLNA play/pause/resume/stop/state/position/relative and absolute seek, bounded UPnP description/UDN import and command/navigation state invalidation.
- [x] Dormant bounded SSDP parser/UDP transport/candidate resolver, with owned loopback tests.
- [x] Files-provider SMB media/caption import with coordinated bounded staging, cancellation/progress/free-space checks and cleanup; UTF-16 and explicit GB18030 subtitle decoding.
- [ ] Production opt-in SSDP discovery/list, Apple multicast entitlement/provisioning and real renderer validation (#114); direct native SMB directory browsing/streaming.
- [ ] HLS/background/resumable/authenticated offline download lifecycle and direct cloud login/QR/OAuth.
- [ ] Optional transcoding sidecar with measured resource limits.
- [ ] Physical iPhone/iPad codec, PiP/AirPlay/background, WebDAV/storage and energy acceptance.

Acceptance: device matrix includes iPhone/iPad models, Safari/Chrome/Firefox, and H.264/H.265/AAC compatibility tests. Automated simulator/owned-fixture success remains distinct from physical acceptance.

## P5 — Multi-device + home server

Tracking: https://github.com/Kahen/TV-Next/issues/6

- [x] Accounts, one-use device pairing, hashed per-device bearer tokens/revocation, per-user ACL and opt-in revision-CAS sync.
- [x] Authenticated WebSocket remote control, expiring handshake tickets and acknowledgements.
- [x] NAS Compose, H2/PostgreSQL migrations, restart/backup restore integration, diagnostics and request correlation.
- [x] Address-bound HTTP/HLS capability relay with pinned DNS/TLS, redirect/header policy, byte/rate/connection/session quotas and revocation.
- [x] EPG scheduling/cache and device-private provider health/search cache.
- [ ] Remote-access deployment hardening, actual remote-NAS operational/security assessment and acceptance.

Acceptance: least-privilege self-hosted service, audited access to user data and consistent playback history on devices.

## P6 — Hardening, distribution and long-tail compatibility

Tracking: https://github.com/Kahen/TV-Next/issues/7

- [ ] Additional provider formats/legacy quirks; explicit compatibility status per module
- [ ] Security reviews: sandbox escapes, SSRF, XSS, content injection, auth, supply chain
- [x] Web npm audit/SBOM, immutable Action/image inputs, gated unsigned Web/API/Linux amd64 candidates with exact source/checksums and host/Docker API JAR byte equality.
- [x] Strict JVM version/checksum evidence, real failure probes and a CycloneDX inventory of the exact shipped API library bytes (#90/#91); vendor maintenance security updates with exact refreshed evidence and version-family regression floors (#93).
- [ ] Independent JVM/container/license review, complete runtime/container SBOM/provenance, signed artifacts and source/notice review
- [ ] Native signing, TestFlight, App Store policy review; no promise of approval
- [ ] Versioned REST contract, migration plan and release channels
- [ ] macOS/tvOS investigation when stable (not required for initial release)
- [ ] Performance budgets: catalog latency, startup time, memory and playback quality

Acceptance: repeatable signed releases, published limitations, reproducible infrastructure and documented rollback.

## Architectural gates (must be verified before implementation expands)

1. P0/P1: Verify that user-provided JSON and M3U can be parsed with no remote execution.
2. P2/P3: Test a small lawful Spider corpus for real Java/JS/Python portability. Abort or narrow scope if plugins rely on Android Context, WebView, JNI or device APIs.
3. P4: Validate codecs and app lifecycle behavior on physical Apple devices, not simulator alone.
4. P5: Conduct a security assessment before exposing any server or media proxy outside a private LAN.

## Release conventions

Initial work lives in feature branches and PRs. Only tested milestones get version tags. Separate Web, Server, and iOS build pipelines; no empty GitHub Release, unverified APK/IPA or pre-signed app claims. Android upstream continues separately in Kahen/TV.

## Historical milestones

The dated entries below describe their original commits, not the current backlog. Use the current phase checklist above for planning.

## 2026-10-23 source-parity implementation increment

See [UPSTREAM_COMPATIBILITY.md](UPSTREAM_COMPATIBILITY.md) for exact original source paths and remaining gaps. Subscription decoding and type 0/1/2/4 HTTP operations now have Web/iOS client paths; AList/OpenList directory and raw-link browsing is implemented; Web/native danmaku parsers and timeline overlays are implemented. P3 type 3 execution, direct cloud account/login flows, remaining P4/P5 modules and P6 release gates remain open. This increment must not be reported as P1–P6 completion.

### P5 account/sync implementation increment

Accounts, per-device tokens, expiring one-use pairing, user-scoped library CAS, Web/iOS controls, WebSocket ticket/ACK remote control, Flyway migrations, H2/PostgreSQL deployment paths and private metrics/request tracing are implemented in the P5 feature branch. Full CI and deployment acceptance are still required before closing any milestone. See HOME_SERVER.md. Provider/EPG scheduling, shared caches and native media byte relay were pending at that historical increment; current implementations and remaining operational gates are listed above.

### EPG subscription and native parity increment

- [x] Account-scoped XMLTV / XMLTV.gz feeds, persistent cache, scheduled updates, last-good-cache recovery and cross-process refresh lease.
- [x] Web and native iOS guide import/display and explicit channel playback; same guide contract fixture across Kotlin/Swift.
- [x] Feed quota, request invalidation, UTF-8 bytes, gzip expansion and XML entity limits implemented with regression coverage.
- [x] Final-head full gate passed in [PR #28](https://github.com/Kahen/TV-Next/pull/28): Web 42, API 62, PostgreSQL 16, native simulator, Compose, NAS and isolation. Remaining P2/P5 acceptance stays open.

### Web dependency security increment

Known-advisory build/test packages are upgraded with a regenerated npm lockfile. Web CI now rejects moderate-or-higher advisories and retains a CycloneDX SBOM and JSON audit report. See [DEPENDENCY_SECURITY.md](DEPENDENCY_SECURITY.md); JVM/container/license/signing/provenance and remaining P6 gates stay open.

## 2026-10-28 live replay increment

Original FongMi timeshift Result resolution and the bounded programme catchup subset now have Web/iOS controls, authenticated capability relay and historical XMLTV views. See [LIVE_REPLAY.md](LIVE_REPLAY.md) for the pinned source mapping, supported date/time tokens, explicit exclusions and regression coverage. [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) reconciles previously merged action/search/AirPlay/Keychain work with the remaining code backlog. P2–P6 are still incomplete.


### P4 native DLNA manual-control increment (#100)

A first iOS AVTransport v1 manual-control slice adds direct SetAVTransportURI/Play/Pause/Stop with explicit LAN renderer endpoint validation and bounded SOAP transport, following FongMi mobile DLNACast. It does **not** fulfill the broader DLNA discovery, renderer interoperability or physical-device acceptance checkbox above. Final-head CI and details: [IOS_DLNA.md](IOS_DLNA.md). Parent P4 #5 stays open.

### P4 native manual DLNA state query (#102)

An opt-in GetTransportInfo status query extends the manually configured private-LAN AVTransport control slice. SwiftUI reports device-acknowledged transport state, distinct from Play/Pause/Stop command acknowledgements; bounded namespace-aware XML parsing rejects invalid or ambiguous values. Owned SOAP fixtures and simulator tests are required before merge. SSDP discovery, physical renderer compatibility and signed distribution remain outstanding. See [IOS_DLNA.md](IOS_DLNA.md).


### Native DLNA position query increment (#104)

- [ ] Read-only iPhone/iPad GetPositionInfo with bounded RelTime/TrackDuration parsing and explicit SwiftUI control; complete only after final-head simulator and aggregate CI. This is not seeking, SSDP discovery or real-device acceptance.

### P4 native manual DLNA bounded REL_TIME seek (#106)

An explicit native iPhone/iPad ±15-second seek control follows FongMi mobile `DLNACast.java` REL_TIME semantics. Each operation checks fresh device transport state and position, requires known finite duration, clamps target, and sends bounded SOAP Seek to the same manually configured private IPv4 renderer. Owned fixture, Swift smoke, XCTest/XCUI and final-head aggregate CI are required. This does not add SSDP, live seeking, real TV compatibility, SMB, or signed distribution. See [IOS_DLNA.md](IOS_DLNA.md).

### P4 native manual DLNA pause/resume slice (#108)

The iPhone/iPad SwiftUI DLNA controls now offer explicit Play resume after an acknowledged pause or reported PAUSED_PLAYBACK. Before resuming, a fresh AVTransport GetTransportInfo must still report PAUSED_PLAYBACK; stopped/playing/transitioning/recording states are rejected. Existing private IPv4, no-redirect/cookie/proxy, 8-second per-request and 32 KiB SOAP bounds apply. This slice is subject to final-HEAD full CI; SSDP, SMB, real renderer and Apple-device acceptance remain pending.


### P4 native DLNA explicit absolute seek (#110)

An iPhone/iPad HH:MM:SS input requests a bounded absolute AVTransport REL_TIME Seek after fresh state and finite-duration queries. Strict ASCII time parsing and rejection of out-of-duration targets avoid surprising playback positions. Owned Swift/loopback/XCTest/XCUI and final-head full CI are required before accepting this increment. No SSDP, real TV, SMB, device validation or signed distribution; parent #5 remains open.

### Native DLNA explicit device-description import (P4, #112)

A user-entered private IPv4 HTTP UPnP device-description URL can be resolved to a single same-origin AVTransport:1 control URL in the native SwiftUI page. Bounded GET, strict XML service selection and negative security fixtures prevent arbitrary remote control endpoint substitution; no SSDP discovery or background scanning is added. Swift smoke, owned localhost network, XCTest, iPhone/iPad XCUI and full final-head CI are required. Parent P4 #5 remains open for actual discovery, SMB, media compatibility and hardware acceptance.

### P4 SSDP response-validation prerequisite (#114)

The native iOS SSDP response parser is implemented as a separate bounded, non-networking prerequisite for eventual opt-in M-SEARCH discovery. It is not an automatic device scan and cannot satisfy the outstanding DLNA discovery checkbox. The actual multicast transport and physical-device validation require Apple's restricted multicast networking entitlement and provisioning. Parser XCTest/smoke and final-head CI evidence belong to its feature PR; parent #5 stays open.

### P4 native DLNA renderer identity on manual import (#116)

Enhance the existing user-entered UPnP description import to display a bounded optional `friendlyName` without new network requests, SSDP discovery or persistence. Strict namespace/path/duplicate/Unicode validation, synthetic HTTP/Swift/XCTest/XCUI regressions and final-head aggregate CI are required before closing this implementation task. P4 #5 and SSDP #114 remain open; hardware and signed release acceptance are separate.

### P4 native WebDAV last-modified metadata (#119)

- [ ] Request and display optional `DAV:getlastmodified` on iPhone/iPad WebDAV listings without a separate network request. Only strict, bounded RFC 1123 GMT values from successful direct DAV propstat are accepted; invalid/duplicate/conflicting/foreign/nested values are omitted. Require Swift positive/negative smoke, owned localhost network, XCTest/XCUI on both simulators and final-head full integration CI. This does not add SMB, offline downloads, external provider acceptance or signed distribution.

### P4 native DLNA optional modelName (#118)

- [ ] Display one bounded, direct UPnP device `modelName` after explicit LAN description import, without changing the control origin, making additional network requests or persisting device metadata. Require positive/negative Swift smoke, owned localhost network fixture, XCTest and production iPhone/iPad XCUI, plus final-HEAD Web/API and full integration CI. Real renderer and physical Apple-device compatibility, SSDP entitlement, SMB and signed distribution remain open.


### P4 native manual DLNA DIDL-Lite metadata (#122)

- [ ] Add opt-in bounded title-based DIDL-Lite for manual SetAVTransportURI, preserving empty metadata by default. Require Swift smoke, owned loopback SOAP/XML positive/negative tests, XCTest/XCUI on both simulators and final-head integration CI. Physical renderer and Apple-device compatibility remain separate.


## P4 iOS Files-provider SMB import (#124)

A user-authorized SMB share mounted in Apple's Files app can be selected through the existing native document picker. NSFileCoordinator and security-scoped access stage a supported media file to a temporary app cache using a streaming 2 GiB limit and partial-file cleanup. This is **not** a native SMB client, remote directory browser or seek-over-SMB playback. See [IOS_SMB_FILES.md](IOS_SMB_FILES.md). Physical SMB/NAS compatibility and final-head CI remain unverified; P4 #5 stays open.

### P4 native Files-provider import cancellation and progress (#126)

A bounded native iPhone/iPad import UI reports actual copied bytes from user-selected Files documents and exposes explicit cancellation. The app cancels and invalidates the worker on user action, backgrounding or library clear, and drops stale results. Synthetic 1 MiB chunk/cancellation/cleanup tests and final-head iPhone/iPad simulator CI are required. Files still owns SMB credentials and hydration; no direct SMB client, real NAS acceptance or Apple-signed release is implied. Parent P4 #5 remains open.


### P4 iOS Files staging orphan reclamation (#128)

Cold app startup reclaims session-only media copies abandoned by a crash or force quit, limited to app-generated UUID-named regular media files in its private staging cache. It does not remove active-session media, user files, symlinks or folders. Swift smoke/XCTest and final-head iPhone/iPad/full CI are required; real SMB/NAS/device compatibility remains open under P4 #5.


### P4 iOS Files/SMB local storage safety (#130)

Native Files-provider media staging now includes a 64 MiB cache-volume free-space reserve preflight for known/unknown source lengths and user-visible disk-full write errors, while retaining the 2 GiB actual-byte limit and partial-copy cleanup. It does not add native SMB browsing/streaming or prove physical NAS behavior. Final-head XCTest/XCUI and full cross-platform integration remain the code acceptance gate; real-device validation remains separate.


### P4 iOS SSDP bounded UDP transport (#132)

A fixed-target, user-initiated native SSDP M-SEARCH UDP transport is implemented as a **dormant service** behind the Apple multicast-entitlement gate. It sends two fixed targets with TTL 1, 3-second deadline, 10-second cooldown and strict response caps; existing private-IPv4 same-sender LOCATION validation is reused. Owned loopback UDP fixture and simulator XCTest/CI are required. **No automatic discovery UI or physical multicast functionality is claimed.** See [IOS_SSDP_DISCOVERY.md](IOS_SSDP_DISCOVERY.md). Parent #114 and P4 #5 remain open.

### P4 iOS Files/SMB subtitle import (#134, 2026-11-01)

The native SRT/VTT/ASS/SSA picker now uses a cancellable background, security-scoped NSFileCoordinator reader with an actual 1 MiB cap instead of synchronous Data(contentsOf:) on the UI actor. Positive/negative Swift tests, iPhone/iPad XCTest/XCUI and final-HEAD integration are required before closing the subtask. Real SMB File Provider and physical-device acceptance remain open. See [IOS_CAPTION_FILES.md](IOS_CAPTION_FILES.md). Parent #5 remains open.

### 2026-11-01 native subtitle encoding increment (#136)

BOM-marked UTF-16LE/BE text subtitle decoding for user-selected Files/SMB SRT/VTT/ASS/SSA is tracked in #136. UTF-8 remains supported, with the existing 1 MiB raw-byte limit and cancellation; BOM-less/legacy encoding detection and real iPhone/iPad SMB provider validation remain outside this code slice. Final-head simulator/full integration evidence is required before completion; parent P4 #5 stays open.

### P4 iOS UPnP root UDN / SSDP identity binding (#138)

The manual native DLNA description import displays a bounded optional root UDN. A pure candidate-promotion check requires the SSDP USN UUID to match the fetched root UDN and preserves the existing private IPv4 same-origin AVTransport policy. Manual import remains usable without UDN. This is an offline/security prerequisite, **not** a shipping automatic SSDP UI, cryptographic authentication, Apple multicast entitlement, real-device verification or P4 completion. See [IOS_SSDP_DISCOVERY.md](IOS_SSDP_DISCOVERY.md).


### P4 native SSDP candidate-to-description resolution (#140)

- [x] On final-HEAD automated acceptance, the dormant iOS resolver validates SSDP candidate metadata before requesting its private-IPv4 LOCATION, fetches through the existing bounded UPnP description transport and requires root UDN/SSDP USN identity plus same-origin AVTransport control. No multicast UI or automatic casting is enabled. Require Swift positive/negative smoke, iPhone/iPad XCTest/XCUI and full aggregate CI. Apple multicast entitlement, real device/renderer validation and parent #114/#5 remain open.


## P4 native iOS explicit GB18030 subtitle import (#142)

The user may explicitly select GB18030 for a **local Files/SMB SRT/VTT/ASS/SSA** import. Default decoding remains strict UTF-8 or BOM-marked UTF-16LE/BE; no legacy encoding sniffing or persisted charset is added. The choice is captured when import starts, while the existing coordinated 1 MiB read, cancellation, old-cue-on-error behavior and private Files Provider credentials remain unchanged. Malformed GB18030 and BOM-marked input in legacy mode are rejected. Remote subscription captions are unaffected. Swift smoke, XCTest and production iPhone/iPad XCUI plus final-HEAD Web/API and full integration CI are required; physical SMB/provider behavior, Apple signing and P4 parent #5 remain unverified.

## 2026-11-02 P2 native cross-provider failure recovery (#144)

Native SwiftUI adds a user-initiated retry for only the failed FongMi search site keys. It preserves already successful provider hits, the originally submitted query and provider order; recovered providers atomically replace any prior partial page without duplicates. Repeated failures retain the last partial hits. The existing 16-site, four-concurrent, two-page and 600-result bounds remain. See [IOS_CROSS_SITE_RETRY.md](IOS_CROSS_SITE_RETRY.md). This is not additional type-3 Spider execution, a permitted real-provider corpus or P2 completion; final-head CI and physical-provider acceptance remain separate.

### P2 native cross-provider result provenance (#146)

Search result labels now use the eligible provider snapshot actually selected for search (first eligible key wins, at most 16), not an earlier hidden/unsupported duplicate key in the raw subscription. Swift positive/negative/cap tests and owned iPhone/iPad XCUI fixture exercise the change. This is a UI attribution correction, not cryptographic provider authentication, real provider corpus validation or P2 completion.


### P2 native cross-site completed-empty feedback (#148)

Native iPhone/iPad cross-site search now has an explicit post-completion zero-result message, distinguishing success from partial or total provider failure and preserving failed-only retry. A synthetic two-provider zero-hit fixture and Swift/XCTest/XCUI cover state transitions and reload clearing. This is not real-provider verification, expanded Spider support or P2 completion; final-head CI and physical-device acceptance remain separate.

### P4 native subtitle preference stale-choice correction (#150)

A nonpersistable explicit AVPlayer subtitle choice now evicts an older saved choice for that title instead of allowing stale restoration. Valid exact track identity and supported Off remain persistent; current playback selection is unaffected. See [NATIVE_EMBEDDED_SUBTITLES.md](NATIVE_EMBEDDED_SUBTITLES.md). Final-head simulator and integration CI are required; P4 parent #5 remains open.

### Native audio/subtitle hidden-option identity collision (#152, 2026-11-02)

AVFoundation may report more than the 16 tracks exposed in the native menu. Previously an invisible duplicate could make a saved visible audio/subtitle name-language identity ambiguous while the restore logic still selected it. The new Foundation-only policy scans the entire option group, restoring only a unique exact identity within the 16 visible choices; later duplicates and unique hidden-only choices leave the system selection untouched. Positive/negative/16–17 boundary Swift smoke, XCTest for both track kinds, final-head iPhone/iPad unsigned simulator build/XCTest/XCUI and Web/API/PostgreSQL/Compose/NAS/Spider isolation are required before merging #152. This does not establish physical media compatibility, external-provider parity, security audit or signed distribution. Parent P4 #5 remains open.

### P4 native per-title audio/subtitle preference reset (#154, 2026-11-02)

The iPhone/iPad AVPlayer menus now provide explicit **future-playback-only** forget actions for the current remote title's remembered audio rendition or embedded subtitle/Off. They preserve the installed item, current selection, progress, other titles and the independent track type; local/replay/no-preference contexts cannot erase another title. Synthetic HLS XCTest and production SwiftUI XCUI plus final-head aggregate CI are the automated acceptance gates. P4 #5 and P6 remain open; no real-device/provider, Spider corpus, independent audit or signing evidence is claimed.

### P2 native search response clipping transparency (#156)

The iPhone/iPad cross-site search UI now distinguishes an oversized individual response (>40 entries) from a provider advertising further pages beyond the two-page budget. Both cases preserve existing limits and provider provenance, and are covered by positive/negative Swift, owned localhost and simulator tests. Final-head CI is required before merging. This does not close P2 #3 or establish licensed provider compatibility.


### P2 native failed-only retry warning reconciliation (#158)

Native cross-site search warning provenance now uses selected provider keys, not localized warning string deduplication. Recovery replaces only the recovered provider's clipping/page-limit warnings alongside its partial hits; a repeated failure retains prior partial-hit warnings. The original 16-site/4-concurrent/2-page/40-item/600-result caps remain. Swift smoke/XCTest, localhost fixture, iPhone/iPad XCUI and full final-HEAD integration gate are required before accepting the slice. No physical-device, authorized external source or signed release claim.

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
