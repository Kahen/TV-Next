# TV-Next roadmap

Updated: 2026-10-28. Current code backlog: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). This is a delivery plan, not a claim that every feature exists.

## Goals and non-goals

Build independent Web/PWA and native iPhone/iPad clients with a shared, optional self-hosted service. Allow users to import authorized external media and FongMi-style configuration files. Do not bundle unauthorized streaming sources, DRM circumvention, site-specific bypasses, or remotely executable untrusted plugins in iOS.

Definition of done for each phase: implementation + automated checks + usage documentation + regression testing + explicit compatibility matrix. See docs/ACCEPTANCE.md for release gates. Each milestone may ship independently. Prioritize functioning vertical slices over superficial feature checklists.

## P0 — Foundations (initial implementation)

- [x] Initialize repository, development branch, docs and architecture
- [x] Web app shell, TypeScript types and basic player
- [x] Kotlin API with health and bounded M3U parsing/config inspection
- [x] SwiftUI iPhone/iPad app scaffold with native AVPlayer
- [x] Web/API CI green; Docker Compose defined (live deployment smoke test pending)
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
- [x] Owned MP4/HLS playback regression on Chromium/Firefox/WebKit; native XCTest and production SwiftUI XCUI workflows for both iPhone/iPad simulators (PR #37 requires a passing final-head gate).

Per explicit user instruction on 2026-10-25, close the implementation issue once code and automated acceptance pass; physical-device/installed-PWA acceptance is independently tracked in [#38](https://github.com/Kahen/TV-Next/issues/38). P1 basic system PiP is implemented; full background-media controls and AirPlay remain P4 implementation tasks (#5).

## P2 — FongMi core semantics

Tracking: https://github.com/Kahen/TV-Next/issues/3

- [x] Source-derived type 0/1/2/4 config decoding, sites/headers/ext/flags, depot selection and Web/iOS browsing.
- [x] Home/category/filter/search/detail/episodes/lines, native/Web bounded cross-provider search with cancellation and partial failure, and the documented HTTP action web workflow.
- [x] M3U/TXT/nested JSON live imports, offline and subscribed XMLTV/XMLTV.gz, persistent guide scheduling/cache and Web/iOS guide UI.
- [x] Explicit timeshift Result RPC, bounded programme catchup subset, historical XMLTV and Web/iOS replay controls; see LIVE_REPLAY.md.
- [x] Native AVPlayer embedded/HLS audio and subtitle selection menus with optional subtitle-off.
- [x] Device-local per-title native audio preferences (#57); per-title embedded/HLS subtitle and explicit-off preferences (#60, PR gates passed).
- [ ] Broader audio/subtitle container and codec compatibility, including track identity changes across providers; device validation remains separate.
- [ ] Broader permitted real-provider corpus, interactive QR/login workflows, parser chains and long-tail replay formats; device validation remains separate.

Acceptance: comparison snapshots for home/category/detail/search/player APIs against a documented compatibility subset.

## P3 — Spider execution compatibility (highest risk)

Tracking: https://github.com/Kahen/TV-Next/issues/4

- [ ] Define versioned Spider provider contract (home/category/detail/search/player)
- [ ] Java 21 static reference JAR now uses a pure-JVM `ProviderSpi` interface. A non-executing, bounded JAR analyzer detects known Android API/JNI/native dependencies; dynamic provider activation, Android API compatibility corpus and permitted real JAR testing remain pending
- [ ] Initial **bundled-fixture-only** Node.js Docker worker with fixed JSON v1 RPC; runtime compatibility with QuickJS and real FongMi JS providers still unimplemented
- [ ] Initial **bundled-fixture-only** Python Docker worker with fixed JSON v1 RPC and OS quotas; real Python Spider library/third-party dependency compatibility unimplemented
- [ ] Docker host harness for Node/Python/Java fixtures uses read-only filesystem, non-root UID, no network, cap-drop, no-new-privileges, pids/memory/CPU/wall-time/output limits; host threat assessment, escape regression and **real plugin execution** not yet complete
- [ ] Error taxonomy: unsupported Android APIs, transport failures, parsing, timeouts
- [ ] Compatibility test corpus: a dozen permitted representative plugins and failure cases

Acceptance: declared supported plugin fixtures pass on server; never execute remote code in the browser or iOS app. JVM bytecode alone is NOT a promise of Android JAR support.

## P4 — Advanced media features

Tracking: https://github.com/Kahen/TV-Next/issues/5

- [x] External SRT/WebVTT timing offset, bounded ASS/SSA Dialogue text, Web/native danmaku parsers and timeline overlays.
- [x] Basic native system PiP and AirPlay route picker; playback speed controls and AList/OpenList browsing.
- [x] Native AVPlayer audio/embedded subtitle selection and bounded per-title audio preferences; per-title subtitle preferences (#60, PR gates passed).
- [ ] Styled ASS positioning/karaoke/fonts, decoder diagnostics, **automatic** intro/outro skip and broader format support remain. Native iOS manual per-title skip markers are implemented in PR #69 (subject to final CI); see [IOS_INTRO_OUTRO.md](IOS_INTRO_OUTRO.md).
- [x] Opt-in native background audio and system play/pause/finite-VOD seek/skip metadata controls; see NATIVE_BACKGROUND_PLAYBACK.md for final-head test gates and limits.
- [ ] Physical background/lock-screen/PiP/AirPlay delivery, quality/codec/energy matrix.
- [ ] Optional transcoding sidecar with measured resource limits.
- [x] Native iOS read-only WebDAV Depth:1 browsing with optional HTTPS Basic credentials and authenticated relay playback (PR #67); bounded incremental PROPFIND response-size hardening is tracked in #70. RFC 4918 successful propstat/direct href correctness is tracked in #72. Physical/provider verification remains open.
- [ ] Authorized LAN DLNA discovery/control and SMB inputs with secure credentials; broader WebDAV auth/provider support remains.
- [ ] Offline cache/download lifecycle and direct cloud login/QR/OAuth.

Acceptance: device matrix includes iPhone/iPad models, Safari/Chrome/Firefox, and H.264/H.265/AAC compatibility tests.

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
- [ ] Automated dependency audits, license attribution and source disclosure
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

## 2026-10-23 source-parity implementation increment

See [UPSTREAM_COMPATIBILITY.md](UPSTREAM_COMPATIBILITY.md) for exact original source paths and remaining gaps. Subscription decoding and type 0/1/2/4 HTTP operations now have Web/iOS client paths; AList/OpenList directory and raw-link browsing is implemented; Web/native danmaku parsers and timeline overlays are implemented. P3 type 3 execution, direct cloud account/login flows, remaining P4/P5 modules and P6 release gates remain open. This increment must not be reported as P1–P6 completion.

### P5 account/sync implementation increment

Accounts, per-device tokens, expiring one-use pairing, user-scoped library CAS, Web/iOS controls, WebSocket ticket/ACK remote control, Flyway migrations, H2/PostgreSQL deployment paths and private metrics/request tracing are implemented in the P5 feature branch. Full CI and deployment acceptance are still required before closing any milestone. See HOME_SERVER.md. Provider/EPG scheduling, shared caches and native media byte relay remain open.

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
