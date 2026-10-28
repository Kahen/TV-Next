# Cross-platform integration and release-verification matrix

This is a **continuously enforced code-level integration plan**, not a substitute for end-to-end playback and physical hardware validation. P1 device/browser UI E2E is deferred to the P6 release gate by current delivery priority; component and cross-language regression checks continue on every relevant change.

| Slice | Source fixture | Enforced check | Actual boundary covered | Still unverified |
| --- | --- | --- | --- | --- |
| M3U | `fixtures/p1-m3u-golden.m3u` and JSON expectation | Swift smoke + Kotlin parser tests | Swift and API normalization agreement | Real playlist variants and Apple device playback |
| FongMi config | In-memory JSON / Swift smoke | Swift Foundation and Kotlin API tests | Safe metadata extraction; no Spider execution | Real Android provider compatibility |
| FongMi Result | `fixtures/p2-fongmi-result.json` | Swift offline parser smoke + Kotlin MockMvc + live Compose nginx/API | Categories, search, details, lines, direct episodes, blocked scripts; same input | Physical AVPlayer playability, source-specific headers and remote providers |
| XMLTV | In-memory deterministic SAX fixture | Kotlin tests + MockMvc + live Compose upload | Timezones, TVG-ID, XXE/DTD rejection, nginx body limits | Real feed updates, native iOS EPG |
| Docker deployment | Clean GitHub Ubuntu runner | `compose-smoke.yml` | Web nginx, Kotlin service, request routing and error semantics | NAS environment / TLS / remote access |
| Spider fixture sandbox | Bundled Node/Python/Java reference code | `spider-sandbox.yml` | OS network denial, cgroups, read-only storage, crash, output bounds, timeout | Real Spider plugins, audited network egress and untrusted-code threat model |
| Native iOS | Swift parser smoke and unsigned Xcode simulator build | `ios.yml`, including `main` pushes with iOS/fixture changes | Swift source compilation and pure parsing | Interactive UIKit/SwiftUI E2E, AVPlayer codecs/PiP on real devices |
| Web | Vitest, TypeScript/Vite build | `ci.yml` | Type-level and component/parser unit behavior | Full browser media/PWA and accessibility E2E |

## CI acceptance rules

1. Any added parser, provider adapter or shared JSON fixture must include success, invalid-input and unsafe-protocol cases where applicable.
2. Contract changes must update the same shared golden fixture, Kotlin tests and Swift smoke where both platforms implement that subset.
3. Docker Compose smoke uses the **same** FongMi Result as both parsers, sends it through real nginx and Spring Boot, and verifies 422 for unsupported episodes.
4. A feature branch may only merge after its affected checks have succeeded. Changing a shared fixture triggers both iOS and Compose checks.
5. Verify the actual merge commit on `main`; record incomplete checks rather than claiming success early.
6. No developer may treat an offline JSON fixture, simulator compile or isolated Spider demo as real source playback, arbitrary plugin compatibility, a signed IPA or a P6 release.

## Deferred release-scale E2E

Before P6 acceptance, run browser automation for playlist import, playback UI, subtitles, favorites, resume, and PWA install in supported browsers. Run real iPhone/iPad media/codecs, Files import/export, navigation, playback interruptions, AVPlayer lifecycle, PiP/AirPlay and accessibility checks; document hardware model and OS versions. Validate authenticated NAS sync, permitted provider corpus, security/audit and signed release provenance. Block release if prerequisites are unavailable.

## Unified full-integration gate (P6 groundwork)

The `.github/workflows/full-integration.yml` **Full Cross-Platform Integration Gate**
invokes four existing workflows at **the same Git revision**, then fails the aggregate
gate if any job is failed, cancelled or skipped:

1. Web Vitest, TypeScript/Vite build, Kotlin Gradle test/bootJar (MockMvc golden Result).
2. Native Swift parser smoke, golden Result parity, unsigned simulator build.
3. Clean Docker Compose boot and nginx-forwarded HTTP tests including XMLTV, FongMi
   config/catalog, and the shared Result home/category/search/detail/episode flow.
4. Node/Python/Java Docker sandbox: no network, read-only FS, resource constraints,
   errors, crash/timeout cleanup, JAR inspection and parity tests.

It triggers on `main` changes to relevant modules, can be run manually, and validates
changes to its workflow orchestration in PRs. The aggregate verification job publishes
a per-subsystem GitHub Actions summary. Only `contents:read` permissions are requested.

**Still outside this gate:** real source-backed Spider integration, full Playwright
browser media/PWA interactions, XCUI physical-device testing, NAS authentication/TLS,
security audit/SBOM, signed/TestFlight distribution. Those P1–P6 launch checks
remain blockers, not implicitly passing because the gate turns green.

## Live replay source-parity increment

`fixtures/fongmi-live-replay-golden.json` anchors Kotlin/Vitest/Swift window and metadata checks. `LiveReplayTest` covers Result RPC vs programme catchup, credentials, UTC/Hong Kong/DST, invalid windows/templates and historical XMLTV bounds; `LiveReplayIntegrationTest` verifies authorize-before-I/O, private capability output and revocation. Native XCTest covers persistence stripping and rejection preserving the player; Web component/browser regressions cover explicit controls, cancellation and original-URL identity. The iOS reusable workflow runs the new shared Swift smoke on both simulator jobs. Final-head aggregate success is required before acceptance; physical/device/provider corpus remains separate.
