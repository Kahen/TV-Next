# Implementation status — 2026-10-25

This is the current code backlog. Physical Apple/device acceptance is deferred to the user after code completion and tracked separately in [#38](https://github.com/Kahen/TV-Next/issues/38). Per user instruction, implementation issues may close after their code and automated checks pass; simulator/fixture results do not close the physical acceptance issue.

| Phase | Implemented code | Remaining implementation / automated coverage |
| --- | --- | --- |
| P1 | Persistent Web/iOS library, favorites/recents/resume, local files, M3U/JSON, SRT/VTT, speed, browser fullscreen/PiP APIs, native fullscreen/system PiP/navigation, lifecycle/error recovery, PWA shell/icons; three-browser E2E and iPhone/iPad XCTest/XCUI gate in PR #37 | Final-head automated gate must pass before closing #2; physical/installed-PWA acceptance is separate #38. See P1_IMPLEMENTATION.md |
| P2 | Source-derived type 0/1/2/4 subscription transport and browsing, live M3U/TXT/JSON, shared Result fixtures, Web/iOS XMLTV, saved XMLTV.gz feeds and scheduled updates | Interactive action/complete catch-up UI, larger permitted corpus, subtitle/audio preferences; bounded cross-provider search (up to 16 sites/2 pages, four concurrent) has deterministic merge and partial-failure regression tests on Web and native iOS; licensed-provider and physical-device acceptance remain outstanding |
| P3 | Java/Node/Python fixed fixture isolation, Java SPI and nonexecuting JAR preflight | Real type 3 JVM/Android/QuickJS/Python adapters, API runtime activation and controlled egress, permitted plugin corpus, security review |
| P4 | SRT/VTT offset, danmaku parser/overlays, AList/OpenList browsing | Styled ASS/SSA (bounded Dialogue text already implemented), embedded track selection, advanced background/AirPlay controls (basic native system PiP in PR #37), DLNA, SMB/WebDAV, optional transcoding/offline lifecycle, direct cloud login/QR/OAuth |
| P5 | Accounts, hashed device tokens, one-use pairing, per-user CAS sync, authenticated WS remote control, H2/PostgreSQL migrations, NAS restart/backup restore, diagnostics, EPG feed scheduling | Remaining remote-access deployment hardening and security/operational acceptance; device-private provider health/search cache shipped in #35 |
| P6 | npm lockfile/ci install, Web dependency audit and CycloneDX SBOM gate, all-or-nothing Web/API/iOS/Compose/Spider/PostgreSQL gate | JVM/container dependency and license/provenance audit, pinned container digests/actions, benchmarks, versioned artifacts/rollback and native signing pipeline |

P5 account core merged in PR #27 after final-head full integration succeeded. Its review finding about a non-writable `/data` default was fixed to a working-directory-relative H2 path; Docker/NAS explicit URLs remain deployment-specific.

EPG increment: Flyway V2 feed/cache schema, account ACLs, atomic refresh leases, stale-cache recovery, enabled-device scheduling, gzip/UTF-8/XXE limits, Web request invalidation and native guide UI. H2/PostgreSQL, Web and native shared contract checks are required for acceptance. See XMLTV_EPG.md. This increment does not complete any entire phase.

Human/resource gates after code completion: real iPhone/iPad playback/lifecycle/codec/energy/network matrix, licensed provider corpus validation, independent security assessment where required, Apple signing/TestFlight credentials and release decision. No signed release has been published.

EPG final-head evidence: [PR #28](https://github.com/Kahen/TV-Next/pull/28), [full gate](https://github.com/Kahen/TV-Next/actions/runs/39977400774). Web 42, API 62 and PostgreSQL 16 passed, with no skipped API/PostgreSQL tests; native shared contract and unsigned simulator, Compose, NAS restart/backup and three-runtime isolation passed.

Media relay increment: device-authenticated in-memory sessions, registered capability URLs, original-origin private headers, pinned DNS/TLS, three revalidated redirects, binary framing/Range validation, bounded HLS rewriting and device-revocation cleanup. Web and iOS retain original URLs in history and never persist relay capabilities. Automated fixture and native build evidence must pass before merge. See MEDIA_RELAY.md; unsupported protocols/DRM/continuous raw live and oversized responses remain explicit limits.

Category-filter increment: original object/list definitions and key/name/init/n/v semantics are bounded and normalized on the API. Web/iOS apply/reset controls retain values through pagination and reset at category/site changes. Kotlin/Web/Swift share a golden fixture; see SUBSCRIPTION_FILTERS.md. Real provider and remaining P2 gates stay open.
