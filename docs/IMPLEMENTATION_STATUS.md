# Implementation status — 2026-10-23

This is the current code backlog. Physical Apple/device acceptance is deferred to the user after code completion; compile/simulator/fixture results do not close that gate.

| Phase | Implemented code | Remaining implementation / automated coverage |
| --- | --- | --- |
| P1 | Persistent Web/iOS library, favorites/recents/resume, local files, M3U, JSON, SRT/VTT, speed, Web fullscreen/PiP, PWA shell | Browser navigation/playback E2E, SwiftUI navigation automation, accessibility/lifecycle/error recovery coverage |
| P2 | Source-derived type 0/1/2/4 subscription transport and browsing, live M3U/TXT/JSON, shared Result fixtures, Web/iOS XMLTV, saved XMLTV.gz feeds and scheduled updates | Filters/action/complete catch-up UI, cross-provider cancellable search, larger permitted corpus, subtitle/audio preferences |
| P3 | Java/Node/Python fixed fixture isolation, Java SPI and nonexecuting JAR preflight | Real type 3 JVM/Android/QuickJS/Python adapters, API runtime activation and controlled egress, permitted plugin corpus, security review |
| P4 | SRT/VTT offset, danmaku parser/overlays, AList/OpenList browsing | ASS/SSA, embedded track selection, native PiP/background/AirPlay controls, DLNA, SMB/WebDAV, optional transcoding/offline lifecycle, direct cloud login/QR/OAuth |
| P5 | Accounts, hashed device tokens, one-use pairing, per-user CAS sync, authenticated WS remote control, H2/PostgreSQL migrations, NAS restart/backup restore, diagnostics, EPG feed scheduling | Native header-dependent media relay with quotas, provider health/search cache and remaining deployment hardening |
| P6 | npm lockfile/ci install, all-or-nothing Web/API/iOS/Compose/Spider/PostgreSQL gate | Dependency/license/SBOM/provenance audit, pinned container digests/actions, browser E2E, benchmarks, versioned artifacts/rollback and native signing pipeline |

P5 account core merged in PR #27 after final-head full integration succeeded. Its review finding about a non-writable `/data` default was fixed to a working-directory-relative H2 path; Docker/NAS explicit URLs remain deployment-specific.

EPG increment: Flyway V2 feed/cache schema, account ACLs, atomic refresh leases, stale-cache recovery, enabled-device scheduling, gzip/UTF-8/XXE limits, Web request invalidation and native guide UI. H2/PostgreSQL, Web and native shared contract checks are required for acceptance. See XMLTV_EPG.md. This increment does not complete any entire phase.

Human/resource gates after code completion: real iPhone/iPad playback/lifecycle/codec/energy/network matrix, licensed provider corpus validation, independent security assessment where required, Apple signing/TestFlight credentials and release decision. No signed release has been published.
