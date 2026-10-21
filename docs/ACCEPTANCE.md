# TV-Next P0–P6 acceptance gates

**A committed feature is not proof of a working feature.** Do not close milestones without reproducible CI, device tests where applicable, compatibility fixtures, security evidence and updated docs.

## Required for every PR

1. Provide scope, supported platforms, reproduction steps and known limits.
2. Run all affected CI checks (Web typecheck/unit tests, Kotlin Gradle tests/bootJar, macOS simulator build when Swift changes).
3. Add success, failure and boundary tests; never use third-party streams as unapproved automated test dependencies.
4. Review no credentials, tokens, unauthorized sources or unsafe plugin execution are bundled.
5. Update OpenAPI/compatibility matrix, docs and issue acceptance checklist.
6. Distinguish verified physical hardware/media tests from compilation or simulator smoke tests.
7. Never publish a signed release or mark a phase complete without verifiable evidence.

## Phase evidence

| Phase | Completion gate | Current blocker |
| --- | --- | --- |
| P0 | Clean checkout, Docker smoke, API/Web/iOS build | GitHub Linux Docker Compose smoke verified; independent NAS deployment and Apple real-device behavior not yet verified |
| P1 | Real iPhone/iPad and browsers HLS/MP4/local media, subtitle/PiP, PWA/a11y, persistence | Physical Apple device/browser matrix pending |
| P2 | Real permitted FongMi corpus: home, category, search, details, episodes, line selection, IPTV XMLTV/EPG; Web and iOS parity | Only static site/live and FongMi Result preview is implemented |
| P3 | Java/JAR, JS and Python permitted Spider fixtures; isolated runtime; egress deny, crash, quota and timeout tests; Android-specific plugin limits disclosed | Bundled fixed-data Node/Python/Java Docker process harness prototyped; dynamic Java/JAR adapter, real Spider compatibility corpus, runtime integration and security review missing; non-executing JVM bytecode preflight is available but is not security approval |
| P4 | Real-device codecs, ASS/danmaku, PiP/background, AirPlay/DLNA, SMB/WebDAV, transcoding when claimed | Major advanced modules unimplemented |
| P5 | Auth, pairing, ACL, backup/restore, TLS, SSRF/DNS rebinding and redirect regression, NAS deployment load test | Secure server services unimplemented |
| P6 | Security threat model/review, dependency/SBOM/license audit, reproducible builds, rollback, compatibility matrix, signed iOS/TestFlight path if required | P1–P5 incomplete, Apple signing/equipment and audit evidence unavailable |

## Release hold

If Apple devices, authorized external fixtures, signing credentials or independent security review are unavailable, mark **BLOCKED**; never invent passed tests, signed IPA artifacts or App Store approval. Physical checks and release decisions require verifiable access.

## Evidence ledger — 2026-10-20

- Web/API and unsigned iOS simulator checks have passed; this does NOT validate actual media playback. A clean GitHub-hosted Linux Docker Compose build/boot and HTTP integration smoke has passed: https://github.com/Kahen/TV-Next/actions/runs/39444315596. Additional expanded endpoint coverage is under PR #14 and requires its own CI evidence. Real NAS installation remains unverified.
- P2 static FongMi catalog and local Result adapter are experimental; they do not execute Spider or connect remote content providers. An offline XMLTV current/upcoming guide slice has unit and controller fixture tests; live XMLTV ingestion, real provider integration and iOS EPG parity are unverified.
- P3 bundled-fixture Docker sandbox harness (Node/Python/Java) is experimental and NOT a real Spider implementation. Isolation CI [run 39449853176](https://github.com/Kahen/TV-Next/actions/runs/39449853176) checks live runtime CPU/memory/PID quotas, host-secret noninheritance, non-root UID, denied network/filesystem writes, crash/output-limit behavior, timeout cleanup and JS/Python result parity. Host daemon security and actual plugin loading remain unverified.
- P3–P6 completion is explicitly **NOT VERIFIED**.
- Link every accepted milestone to exact PR/commit/Actions run, test fixture version, real test devices and results.
