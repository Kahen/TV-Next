# Implementation status — 2026-10-29

This is the current code/acceptance inventory. Historical issue comments and older
milestone ledgers describe their own commits; an unchecked old checkbox is not
proof that current code is missing. PRs #79–#91 contain the latest implementation increments;
only merged changes with passing final-head CI count as delivered on main.

| Phase | Implemented code | Remaining implementation | External acceptance |
| --- | --- | --- | --- |
| P1 | Web/iOS persistent libraries, imports/export/local files, favorites/history/resume, player controls, PWA shell, real-browser and iPhone/iPad simulator acceptance; #2 closed | No reopened P1 implementation task | Physical Apple devices and installed PWA, #38 |
| P2 | Source-derived type 0/1/2/4 subscriptions, categories/filters/search/details/lines, bounded cross-site search, HTTP action web subset, live imports/XMLTV.gz scheduling, bounded timeshift/catchup; native AVPlayer audio/subtitle preferences; native subscription external captions in #80 | Interactive login/QR actions, parser/WebView chains, wider replay/provider variants, broader Web track/preference parity | Permitted representative provider corpus and real playback, #3 |
| P3 | Bundled Java/Node/Python fixture workers and OS-isolation tests; bounded nonexecuting JAR/DEX preflight; administrator-bound Android SpiderTest bridge, five media operations, device auth and Web/iOS capability UI; #85 adds a preflighted/hash-checked owned-JAR loader using original Spider media signatures inside the OS sandbox | External pure-JVM artifact/dependency approval and representative corpus (#45), authorized dispatcher/API activation, real JS/QuickJS/Python adapters, controlled egress and stateful Android sessions/actions/proxy callbacks | Actual ARM Android DEX/native execution, permitted plugin corpus and independent isolation/security review, #4 |
| P4 | External SRT/VTT/text ASS/SSA, offsets/danmaku; native PiP/AirPlay/audio/subtitle preferences/background controls; AList/OpenList and read-only WebDAV; native manual markers; #79 fixes exact collection hrefs/breadcrumbs; #80 adds opt-in marker auto-skip, offline media files, native subscription captions and stale-resource cancellation; #84 adds offline deletion confirmation/storage usage; #86 adds private read-only codec/buffer/error diagnostics; #89 binds WebDAV requests/playback to immutable connection credentials | Styled ASS/fonts/karaoke, broader subtitle matching/headers, SMB/DLNA, HLS/background/resumable downloads, optional transcoding, direct cloud login/QR/OAuth and automatic skip detection/provider metadata | Physical codec/seek/PiP/AirPlay/background/WebDAV/storage/energy matrix, #5 and #38 |
| P5 | Accounts, hashed device tokens, one-use pairing/revocation, CAS library sync, authenticated WS remote, H2/PostgreSQL/NAS restart/restore, diagnostics, EPG scheduling, private provider health/cache and bounded DNS-pinned HTTP/HLS relay | Remaining remote-access deployment controls and operational hardening | Actual NAS/remote-network restore/load/ACL/egress assessment, #6 |
| P6 | npm lock/audit/CycloneDX SBOM; all-or-nothing Web/API/PostgreSQL/browser/native/Compose/NAS/isolation gate; #81 pins Actions and Docker inputs with official metadata provenance and CI drift rejection; #82 builds gated unsigned Web/API/Linux amd64 candidates with matching source, Web SBOM/audit and checksums; #88 requires host/Docker API JAR byte equality; #90 locks API/tooling versions and verifies artifact/metadata SHA-256; #91 inventories exact shipped JVM library bytes | Independent JVM/container/license review, runtime/container SBOM/provenance beyond API libraries, measured performance budgets, signed/ARM/native artifacts, broader reproducibility and actual rollback/distribution acceptance | Independent security/license review, Apple signing/TestFlight/distribution decision, #7 |

## This iteration

- [#79](https://github.com/Kahen/TV-Next/pull/79): WebDAV root/ancestor navigation
  is bounded to validated canonical paths. Directory hrefs preserve exactly one
  existing trailing slash: Darwin `URL.path` previously caused `/Folder//` and a
  real nested PROPFIND 404. The localhost fixture consumes request bodies before
  closing, so TCP resets cannot masquerade as response-size failures. See
  [IOS_WEBDAV.md](IOS_WEBDAV.md).
- [#80](https://github.com/Kahen/TV-Next/pull/80): completed native offline media
  file copies survive restart and can be played/deleted. The foreground transfer
  has cancellation, format/status/size validation and bounded storage; source
  URLs/headers/resume blobs are excluded from its manifest. HLS/DRM, background,
  range resumption and authenticated media downloads remain pending. See
  [IOS_OFFLINE_MEDIA.md](IOS_OFFLINE_MEDIA.md).
- The same PR adds per-title opt-in automatic skipping of user-created markers,
  once per boundary per playback, with explicit-seek suppression. It does not
  detect intros or advance to an unselected next episode. See
  [IOS_INTRO_OUTRO.md](IOS_INTRO_OUTRO.md).
- Subscription external subtitles now reach native AVPlayer text overlays via
  the existing bounded text API. Switching media/server, selecting a newer
  subtitle, importing/removing captions or backgrounding invalidates pending
  loads. Subtitle and danmaku late responses cannot overwrite a newer playback.
- [#81](https://github.com/Kahen/TV-Next/pull/81): all existing external Actions
  use actual commit IDs; Dockerfiles and Compose/CI services use platform-index
  digests. `build-inputs.lock.json` records the source commit/path/blob for image
  metadata, and CI rejects mutable/unreviewed references. This freezes inputs;
  it does not establish vulnerability freedom or bit-identical outputs. See
  [BUILD_INPUT_PINS.md](BUILD_INPUT_PINS.md).

- [#82](https://github.com/Kahen/TV-Next/pull/82): gated unsigned candidate bundles
  contain the exact GPL source, Web, versioned API JAR, Linux amd64 images, Web
  audit/SBOM, immutable input lock, OCI identities and SHA256SUMS. PR CI exercises
  real packaging and archive reload; manual dispatch first runs the full gate.
  Draft Release creation is explicit and main-only. No public release or signed
  IPA is created automatically. See [RELEASE_CANDIDATES.md](RELEASE_CANDIDATES.md).

- [#84](https://github.com/Kahen/TV-Next/pull/84): native offline deletion has an
  explicit cancel/confirm path. Cancel preserves playback and the file; confirm
  releases only that file's player item. Storage usage is visible. Final-head
  [full gate](https://github.com/Kahen/TV-Next/actions/runs/40876129955) passed.
- [#85](https://github.com/Kahen/TV-Next/pull/85): a separate RPC v2 CLI harness
  loads an actual owned, pinned and statically preflighted JAR through original
  FongMi init/home/category/detail/search/player/destroy signatures. Container
  isolation and bounded teardown remain the boundary; there is no external JAR
  upload or new live API activation. Final-head [full gate](https://github.com/Kahen/TV-Next/actions/runs/40882224143) passed. See [PURE_JVM_SPIDER.md](PURE_JVM_SPIDER.md).
- [#86](https://github.com/Kahen/TV-Next/pull/86): native AVPlayer diagnostics show
  encoded codec/dimensions/audio parameters, timeline/buffer state and sanitized
  errors. No raw URL, headers or error logs are shown or persisted. This does not
  identify a hardware decoder. Final-head [full gate](https://github.com/Kahen/TV-Next/actions/runs/40889089374) passed: each iPhone/iPad ran 52 unit and 13 UI tests. See [NATIVE_PLAYBACK_DIAGNOSTICS.md](NATIVE_PLAYBACK_DIAGNOSTICS.md).

- [#88](https://github.com/Kahen/TV-Next/pull/88): the independently compiled host
  and Docker API JARs must match byte for byte before candidate packaging. The
  [candidate gate](https://github.com/Kahen/TV-Next/actions/runs/40887628529) passed.
  This is scoped API binary equality, not universal container reproducibility.
- [#89](https://github.com/Kahen/TV-Next/pull/89): editing an unconnected WebDAV
  form cannot change the active root/credentials used by browsing or playback.
  Authorization is root/origin/scheme/port scoped and credential bounds count
  UTF-8 bytes. Native UI refreshes the active owned fixture after draft edits.
- [#90](https://github.com/Kahen/TV-Next/pull/90): 132 exact API/tooling module
  versions and 519 artifact/metadata SHA-256 values are committed. CI never
  regenerates the baseline. Real Gradle negative probes reject wrong checksums
  and missing lock state, including warm-cache behavior. See
  [JVM_DEPENDENCY_INTEGRITY.md](JVM_DEPENDENCY_INTEGRITY.md).
- [#91](https://github.com/Kahen/TV-Next/pull/91): API CI and candidates inventory
  the actual embedded library bytes in CycloneDX JSON, with exact Maven identities,
  hashes and archive paths. Unknown/changed libraries fail generation. The unused
  Spring Boot jarmode extraction tool is excluded from the directly launched API.
  This is a flat library inventory; dependency edges, license/vulnerability clearance
  and JDK/OS coverage are not inferred. See [JVM_RUNTIME_SBOM.md](JVM_RUNTIME_SBOM.md).

## Remaining code, in priority order

1. **Real Spider compatibility:** validate the supplied Android/native subscription
   on an ARM FongMi host; extend the owned-JAR contract slice to an approved
   external pure-JVM corpus/dependency policy, authorized API activation, real
   JS/Python adapters, stateful/proxy behavior and controlled egress. The static
   fixture SPI and the new approved-JAR loader are separate, explicitly scoped paths.
2. **Native media compatibility:** SMB/DLNA, advanced ASS/subtitle behavior, direct
   cloud account workflows, HLS/background/resumable offline lifecycle and optional
   resource-limited transcoding. Keep browser completion lower priority than
   functioning iPhone/iPad paths, per the user's instruction.
3. **Protocol parity:** parser chains and interactive actions, remaining Web track
   preferences and long-tail live/provider behavior. Publish exact support and
   failure behavior for each tested variant.
4. **Server operations:** remaining remote-access deployment hardening and measured
   ACL/egress/sync/restore reliability on the intended NAS/network topology.
5. **Distribution:** independent JVM/container/dependency/license evidence, full
   runtime/container SBOM and release provenance, measured budgets, ARM/native/signature
   support, broader reproducibility, rollback drills and Apple signing/TestFlight.
   Unsigned candidate packaging, API binary equality, JVM version/checksum baselines
   and the shipped-library SBOM are implemented in #82/#88/#90/#91; these increments
   do not complete the remaining distribution gates.

## Evidence and resource gates

Automated tests use owned/synthetic media and contracts. Real subscription loading
was previously verified, but the supplied plugin contains DEX and ARM native guard
libraries, not JVM classes. Loading its config is not successful provider execution.
See [REAL_SPIDER_COMPATIBILITY.md](REAL_SPIDER_COMPATIBILITY.md) and
[ANDROID_SPIDER_BRIDGE.md](ANDROID_SPIDER_BRIDGE.md).

Physical device/installed-PWA acceptance remains #38. Actual Android/plugin
execution, a permitted representative corpus, independent security/license review
and signed Apple distribution need separate evidence. Do not close P2–P6 parent
issues or label the project release-ready while the remaining code or those gates
are open. Track each passing implementation separately from device acceptance.
