# Cross-platform integration and release-verification matrix

Updated 2026-11-04. The full gate verifies actual owned-fixture browser playback and production SwiftUI on iPhone/iPad simulators, in addition to compilation, unit tests and service integration. Physical Apple/TV/NAS devices, third-party sources and signed distribution remain separate acceptance work.

| Slice | Enforced check | Verified boundary | Still unverified |
| --- | --- | --- | --- |
| Shared M3U/Result/filter/replay/EPG contracts | Kotlin/Vitest/Swift golden fixtures and MockMvc | Same source-derived normalization and supported RPC semantics across clients | Wider permitted provider corpus |
| Web/API | `ci.yml` | Web unit/type/build/audit/SBOM; Kotlin test/bootJar; PostgreSQL account/remote/EPG migration tests; exact JVM-library SBOM | Complete dependency/license audit and production load |
| Browser media and Docker | `compose-smoke.yml` | Clean images, nginx/API HTTP, real Chromium/Firefox/WebKit MP4/HLS decode, library/resume/caption and shell-cache assertions | Physical installed-PWA matrix and third-party CORS/codec variants |
| Native iOS | `ios.yml`, iPhone and iPad jobs | Swift smoke, owned network fixtures, unsigned build, XCTest and production SwiftUI XCUI with generated local media | Physical AVPlayer/codecs/PiP/AirPlay, Files providers and energy behavior |
| NAS/account/sync/remote | `nas-integration.yml` | Actual Docker PostgreSQL stack, HTTP/WebSocket ownership/handshake, restart persistence, backup/restore | User NAS environment, TLS/remote-network/security/load acceptance |
| Spider isolation | `spider-sandbox.yml` | Java/Node/Python fixture parity, actual owned-JAR loading, preflight, no-network/read-only/non-root quotas and teardown/failure checks | External JVM registry/dispatcher/egress, real JS/Python, ARM Android corpus and independent containment audit |
| JVM integrity | `jvm-dependency-integrity.yml` | Strict pinned-toolchain build; real wrong-checksum/missing-lock rejection probes | Independent publisher/provenance/license review |
| Unsigned release candidate | `release-candidate.yml` | Web/API/Linux amd64 packaging, corresponding source/checksums, exact shipped-library SBOM and independent host/Docker JAR byte equality | ARM/native/signed artifacts, full image SBOM, rollback and Apple distribution |

## Aggregate gate

[Full Cross-Platform Integration Gate](../.github/workflows/full-integration.yml) calls **five** reusable workflows at the same revision: Web/API, iOS, Compose/browser, Spider isolation and NAS. Its final verification job rejects failed, cancelled or skipped subsystem results. iPhone and iPad run independently with matrix fail-fast disabled so one failure does not erase the other's evidence.

The gate runs on relevant code, fixture, script, contract and workflow PR/main changes, or explicit dispatch. Document-only changes do not trigger the full gate; normal Web/API PR checks still run. JVM-integrity and unsigned-candidate checks are additional path-selected workflows for affected dependency/build changes.

The candidate workflow's PR path only packages. Its reusable gate and draft-release jobs are intentionally skipped on PR events; the independently triggered full integration workflow must still pass before merging. A manual candidate dispatch runs its own full gate, and creating a draft Release is a separate explicit input. A successful package job is not a published Release.

## Acceptance rules

1. Require final-head affected checks, including the aggregate gate for code changes; a previous green commit does not cover later edits.
2. Record exact PR/commit/run and test evidence. Check the actual merge revision on main and report pending results accurately.
3. Shared protocol changes update the common fixture and applicable Kotlin/Swift/Web tests, including rejected inputs and stale/cancelled result behavior.
4. No retries, skipped assertions or removed resource/security limits may stand in for diagnosing a failure. See [PR #172](https://github.com/Kahen/TV-Next/pull/172) for the fixed minute-window and early-413 test races.
5. Owned local media, fixtures, simulators and container tests do not establish external source availability, arbitrary Spider compatibility, physical-device operation or signed release acceptance.

## Remaining release verification

Physical iPhone/iPad and installed PWA testing remains [#38](https://github.com/Kahen/TV-Next/issues/38). Validate actual codecs, Files/SMB hydration, LAN renderer behavior, PiP/AirPlay/background interruptions, permissions, storage and energy use with recorded hardware/OS/builds. Complete the permitted provider/plugin corpus, remote NAS security/operations, independent dependency/license/containment review, rollback exercises and signing/provenance requirements in P2–P6. These resource gates do not block independent implementation work.
