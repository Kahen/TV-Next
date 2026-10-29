# Implementation status — 2026-10-28

Verified repository baseline at the start of this slice: `main` at `a9797ef` (PR #63), plus the current PR's explicitly described changes. This table reconciles code with older open issue checklists; it does not treat an unchecked historical issue item as proof that current code is missing. Final-head automated evidence belongs to the associated PR.

| Phase | Implemented code | Still unfinished |
| --- | --- | --- |
| P1 | Persistent Web/iOS library, favorites/recents/resume, imports/export/local files, external subtitles, speed/fullscreen/basic native PiP, lifecycle recovery, PWA shell, browser and iPhone/iPad simulator tests; implementation #2 closed | Physical iPhone/iPad and installed-PWA matrix stays open in #38 |
| P2 | Source-derived type 0/1/2/4 decoding/browsing, category filters, action web workflow, bounded cross-site search on Web/iOS, M3U/TXT/JSON live imports, persistent XMLTV.gz subscriptions; this increment adds timeshift Result resolution, bounded programme catchup and Web/iOS controls | Broader permitted real-provider corpus, arbitrary interactive QR/login actions, parser/WebView chains, broader subtitle/audio compatibility; replay long-tail outside the documented subset and real-device acceptance |
| P3 | Bundled Java/Node/Python fixture workers, OS isolation harness, Java SPI and nonexecuting bounded JAR/DEX preflight; optional administrator-bound Android SpiderTest bridge with five media methods and Web/iOS capability UI | Actual ARM Android bridge/plugin execution and media acceptance, stateful/proxy support, vetted pure-JVM FongMi Spider JAR loader (#45), real QuickJS/JS/Python adapters/dependencies, controlled egress, representative plugin corpus and security review (#4) |
| P4 | SRT/VTT offset, bounded ASS/SSA dialogue text, danmaku parsers/overlays, AList/OpenList browsing, basic native PiP/AirPlay, native AVPlayer audio/subtitle selection and per-title preferences, opt-in background audio/system controls; read-only iOS WebDAV with secure relay (#67); manual per-title intro/outro markers (PR #69 pending gate) | Styled ASS/advanced matching, physical background/lock-screen and WebDAV acceptance, automatic intro/outro skip, DLNA, SMB, offline download lifecycle, optional transcoding, direct cloud login/QR/OAuth and device codec/energy verification (#5) |
| P5 | Accounts, hashed device tokens, pairing/revocation, per-user CAS sync, authenticated WS remote, H2/PostgreSQL/NAS persistence and restore, diagnostics, EPG scheduling, device-private provider health/search cache, bounded HTTP/HLS capability media relay | Remote-access deployment hardening, security/operational assessment and actual NAS/remote-network acceptance (#6) |
| P6 | Committed npm lockfile, npm audit/CycloneDX SBOM, aggregate Web/API/PostgreSQL/browser/iOS/Compose/NAS/sandbox CI | JVM/container dependency and licence/provenance audit, immutable image/action pins, performance/reliability benchmarks, reproducible versioned artifacts/rollback, native signing/TestFlight/distribution (#7) |

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
