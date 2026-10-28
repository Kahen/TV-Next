# Implementation status — 2026-10-28

Verified repository baseline: `main` at `1bb74b0` (PR #51). This table reconciles code with older open issue checklists; it does not treat an unchecked historical issue item as proof that current code is missing. This increment adds original live replay semantics; final-head automated evidence belongs to the associated PR.

| Phase | Implemented code | Still unfinished |
| --- | --- | --- |
| P1 | Persistent Web/iOS library, favorites/recents/resume, imports/export/local files, external subtitles, speed/fullscreen/basic native PiP, lifecycle recovery, PWA shell, browser and iPhone/iPad simulator tests; implementation #2 closed | Physical iPhone/iPad and installed-PWA matrix stays open in #38 |
| P2 | Source-derived type 0/1/2/4 decoding/browsing, category filters, action web workflow, bounded cross-site search on Web/iOS, M3U/TXT/JSON live imports, persistent XMLTV.gz subscriptions; this increment adds timeshift Result resolution, bounded programme catchup and Web/iOS controls | Broader permitted real-provider corpus, arbitrary interactive QR/login actions, parser/WebView chains, subtitle/audio preferences; replay long-tail outside the documented subset and real-device acceptance |
| P3 | Bundled Java/Node/Python fixture workers, OS isolation harness, Java SPI and nonexecuting bounded JAR preflight | Vetted pure-JVM FongMi Spider JAR loader (#45), versioned host dispatcher/API activation, real QuickJS/JS/Python adapters/dependencies, controlled egress, permitted representative plugin corpus, security review (#4) |
| P4 | SRT/VTT offset, bounded ASS/SSA dialogue text, danmaku parsers/overlays, AList/OpenList browsing, basic native PiP and system AirPlay route picker; native AVPlayer audio and embedded/HLS subtitle selection, device-local per-title audio preference (pending final-head CI) | ASS styling/position/karaoke/fonts, per-title subtitle preferences (#59 pending final-head CI) and broader audio matching, background/lock-screen media controls, intro/outro skipping, DLNA, WebDAV/SMB, offline download lifecycle, optional transcoding, direct cloud login/QR/OAuth and device codec/energy verification (#5) |
| P5 | Accounts, hashed device tokens, pairing/revocation, per-user CAS sync, authenticated WS remote, H2/PostgreSQL/NAS persistence and restore, diagnostics, EPG scheduling, device-private provider health/search cache, bounded HTTP/HLS capability media relay | Remote-access deployment hardening, security/operational assessment and actual NAS/remote-network acceptance (#6) |
| P6 | Committed npm lockfile, npm audit/CycloneDX SBOM, aggregate Web/API/PostgreSQL/browser/iOS/Compose/NAS/sandbox CI | JVM/container dependency and licence/provenance audit, immutable image/action pins, performance/reliability benchmarks, reproducible versioned artifacts/rollback, native signing/TestFlight/distribution (#7) |

## Live replay increment

See [LIVE_REPLAY.md](LIVE_REPLAY.md). Reference: original **FongMi/TV `123cc086159b0f13bf54bdf64bacbc259ca47c88`**, `Timeshift`, `TimeshiftPlayback`, `Catchup`, `Channel`, `LiveParser`.

- Timeshift uses Unix milliseconds, the explicit provider window and a zero live sentinel; its URL returns Result JSON, not video. Programme catchup is a separate bounded start/end path.
- Both clients have explicit time selection, return-to-live, cancellation and error feedback; XMLTV adds up to 40 historical programmes/channel. Failed resolution retains current playback.
- Authorization precedes provider I/O. DNS-pinned text/media transports, credential scope and relay quotas/revocation are reused. Private provider URLs/headers are not returned in the replay response.
- Replay templates/capabilities and replay progress are excluded from persisted/synced libraries. Clients must reload subscriptions after restart to restore replay metadata.
- Shared Kotlin/Swift/Vitest golden fixtures, MockMvc authorization/revocation, native snapshot/player tests and browser regression supplement the existing full gate. Automated fixture success does not establish licensed real-provider or physical-device acceptance.

Do not close parent P2/P3/P4/P5/P6 issues from this subset. No signed Release/IPA/TestFlight package has been published. Human/resource gates remain: physical devices, permitted external plugin/provider corpus, independent security assessment and Apple distribution credentials/release decision.
