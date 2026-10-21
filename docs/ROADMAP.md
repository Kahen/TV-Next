# TV-Next roadmap

Updated: 2026-10-20. This is a delivery plan, not a claim that every feature exists.

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

Tracking: https://github.com/Kahen/TV-Next/issues/2

- [x] Implement device-local persistence for playlists, recents, favorites and finite-VOD playback progress (Web unit-tested, iOS simulator build-tested; cross-device sync not yet available)
- [ ] Support JSON config import (file/paste) and site display; reject oversized data
- [x] Initial playlist group display, search, and favorites on Web/iOS (full accessibility audit pending)
- [ ] Web compatible local file picker and iOS security-scoped local-file staging implemented; codec/format playback and device storage testing remain
- [ ] Web and iOS speed selectors, Web fullscreen/PiP best-effort controls added; native and device verification still pending
- [ ] PWA manifest + shell-only service worker added; real install tests, iPad Split View, orientation and accessibility remain
- [ ] UTF-8 SRT/WebVTT implemented on Web and iOS (native caption overlay); M3U export on both, E2E and API contract tests remain

Acceptance pending: equivalent catalog handling and history semantics across Web/iOS using golden fixtures, browser restrictions (CORS/codecs) documented, actual device tests. Device-local storage is NOT synchronization.

## P2 — FongMi core semantics

Tracking: https://github.com/Kahen/TV-Next/issues/3

- [ ] Initial FongMi site/live/group/channel metadata normalization + Web browsing + optional direct HTTP(S) live playback; headers/flags, nested references and full config compatibility still pending
- [ ] Static FongMi Result adapter provides local home/category/search/detail/line/episode APIs; genuine network providers, cross-site queries and compatibility tests with permitted real fixtures remain
- [ ] FongMi nested live JSON metadata preview and offline XMLTV import/EPG channel matching implemented on Web/API. Full M3U/TXT/JSON live imports, auto EPG updates, iOS EPG, replay and timeshift remain
- [ ] Subtitle tracks (WebVTT/SRT) and per-title audio preferences
- [ ] Cross-provider search with cancellation, timeout, pagination and deduplication
- [ ] Structured golden fixtures from sources with permission to test

Acceptance: comparison snapshots for home/category/detail/search/player APIs against a documented compatibility subset.

## P3 — Spider execution compatibility (highest risk)

Tracking: https://github.com/Kahen/TV-Next/issues/4

- [ ] Define versioned Spider provider contract (home/category/detail/search/player)
- [ ] Java 21 self-contained, static reference JAR now executes under the same default-deny Docker sandbox with parity tests. Real pure-JVM Spider JAR adapter, Android API detection and permitted external JAR compatibility tests still pending
- [ ] Initial **bundled-fixture-only** Node.js Docker worker with fixed JSON v1 RPC; runtime compatibility with QuickJS and real FongMi JS providers still unimplemented
- [ ] Initial **bundled-fixture-only** Python Docker worker with fixed JSON v1 RPC and OS quotas; real Python Spider library/third-party dependency compatibility unimplemented
- [ ] Docker host harness for Node/Python/Java fixtures uses read-only filesystem, non-root UID, no network, cap-drop, no-new-privileges, pids/memory/CPU/wall-time/output limits; host threat assessment, escape regression and **real plugin execution** not yet complete
- [ ] Error taxonomy: unsupported Android APIs, transport failures, parsing, timeouts
- [ ] Compatibility test corpus: a dozen permitted representative plugins and failure cases

Acceptance: declared supported plugin fixtures pass on server; never execute remote code in the browser or iOS app. JVM bytecode alone is NOT a promise of Android JAR support.

## P4 — Advanced media features

Tracking: https://github.com/Kahen/TV-Next/issues/5

- [ ] ASS/SSA styling, multiple subtitles, subtitle offset, Danmaku overlay
- [ ] Audio track/channel selection, decoder capability diagnostics, speed, skip intro/outro
- [ ] Native iOS: AVPlayer/PiP/background media, AirPlay; evaluate alternate player SDK licensing
- [ ] Optional transcoding sidecar for media not supported natively; measure CPU/bandwidth
- [ ] DLNA discovery/control in a LAN-capable service; iOS local-network permissions
- [ ] Media ingestion from authorized WebDAV/SMB/DLNA/local files
- [ ] Offline cache/download lifecycle for downloadable content where authorized

Acceptance: device matrix includes iPhone/iPad models, Safari/Chrome/Firefox, and H.264/H.265/AAC compatibility tests.

## P5 — Multi-device + home server

Tracking: https://github.com/Kahen/TV-Next/issues/6

- [ ] Account, device pairing, API keys, per-user ACL and opt-in sync
- [ ] WebSocket remote control with device authorization and expiring pairing codes
- [ ] NAS Docker Compose deployment; PostgreSQL migrations; optional Redis caching
- [ ] Metrics, structured logs, tracing and failure dashboards
- [ ] Safe SSRF-resistant proxy limited to approved destinations; byte/rate/connection caps
- [ ] Secure remote access/TLS guidance; backups/import-export, conflict resolution
- [ ] EPG scheduling, provider health reporting and search caching

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
