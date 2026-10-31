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

## Native WebDAV completion-status CI regression (#74)

The 2026-10-29 main push full gate [40809764313](https://github.com/Kahen/TV-Next/actions/runs/40809764313) failed in the iPad-only localhost WebDAV network smoke with `invalidResponse`, despite the iPhone and other jobs succeeding. This follow-up adds a final-task-response HTTP status/length fallback, explicit EOF for unknown-length localhost fixtures, and positive/negative/size-boundary transport regressions. It does not weaken redirect rejection, byte caps or credential handling, and it is not evidence of real-device/provider acceptance. Final-head iPhone/iPad and aggregate CI must succeed before merging this slice.

## Native WebDAV local browse controls (P4, #76)

The SwiftUI WebDAV view adds explicit current-folder refresh and device-local filename/media-only filtering over the previously bounded Depth:1 listing. The filter never changes server requests, URL paths, headers or credentials; folders remain navigable in media-only mode, and the first-200-entry cap still applies. Refresh preserves the last successful listing on failure and rejects stale asynchronous responses through the existing request generation guard. Swift smoke, XCTest and production XCUI against the owned localhost PROPFIND fixture cover positive/negative UI, filtering, refresh and disconnect behavior; final-head full CI and physical/provider acceptance remain separate.

## Native WebDAV bounded breadcrumb navigation (P4, #78)

Native SwiftUI adds direct root/ancestor shortcuts for nested WebDAV folders. A pure Swift helper derives at most 32 canonical directory ancestors from already root-validated URLs, rejecting foreign origins, sibling roots, non-directory inputs and over-depth paths. The UI invokes the existing bounded/cancelable directory fetch, not a new transport. Swift smoke, XCTest and iPhone/iPad XCUI against the owned localhost nested-folder fixture provide positive/negative regression coverage. Final-head aggregate CI and physical-provider validation remain distinct.

## Native offline deletion confirmation (P4, #83)

Offline copies now require an explicit destructive confirmation before deletion.
Cancel preserves the file, catalog entry and any active AVPlayer item; confirm
releases only the matching local player item and removes the copy. The native
section displays the current count and byte usage against the existing quota.
Production iPhone/iPad XCUI covers owned-fixture download, relaunch, playback,
cancel and confirm. See [IOS_OFFLINE_DELETE.md](IOS_OFFLINE_DELETE.md).
Final-head simulator/integration gates and physical-device acceptance are distinct;
this does not implement resumable/HLS/DRM downloads, SMB/DLNA or signed releases.

## Native WebDAV folder-first sorting (P4, #96)

The native connected-directory view now offers a local ascending/descending natural filename sort. Folders remain first; a deterministic URL tie-breaker avoids unstable equal-name ordering. The selected order survives directory navigation and refresh but resets on new connection/disconnect. This does not change Depth:1 requests, the 200-entry limit, credential handling or media relay. Positive/negative/boundary Swift smoke and XCTest plus production SwiftUI XCUI are added; final-head CI, physical-device and external-provider verification are separate. Parent P4 #5 remains open.

## Native WebDAV bounded file sizes (P4, #98)

Read-only native WebDAV requests optional `DAV:getcontentlength` in the same Depth:1 listing, displays validated file byte counts and omits unknown/folder sizes. Successful direct DAV propstat scope and 0–8 TiB decimal bounds prevent malformed/foreign/failed metadata from being shown. No extra network request, credential persistence, server-side sort, SMB/DLNA or device acceptance is implied. Final-head Swift smoke/XCTest/XCUI and full integration evidence belong to issue #98; parent #5 stays open.


## Native manual DLNA AVTransport subset (P4, #100)

Native SwiftUI now exposes a manually entered LAN AVTransport control URL and direct HTTP(S) media URL. A bounded SOAP v1 client issues SetAVTransportURI → Play, and separate Pause/Stop, following FongMi's mobile DLNACast sequence. Renderer endpoints are restricted to explicit private/loopback IPv4 HTTP literals; redirects, credentialed URLs and oversized/malformed SOAP responses are rejected. A synthetic localhost fixture and iPhone/iPad XCTest/XCUI cover positive/negative paths; **final-head CI is required before accepting this increment**. This is not SSDP discovery, real renderer/codec interoperability, credentialed media relay, signed distribution or physical-device acceptance. See [IOS_DLNA.md](IOS_DLNA.md). P4 #5 remains open.

## Native DLNA read-only transport status (P4, #102)

A native iPhone/iPad manual renderer now supports explicit AVTransport v1 GetTransportInfo and a read-only status button, reusing the bounded SOAP transport. The parser requires one direct CurrentTransportState in the correct SOAP action response and accepts only known UPnP state values; invalid/nested/duplicate/foreign values fail closed. A stateful owned fixture, positive/negative Swift smoke, XCTest and production XCUI test the reported transitions. Final-head CI evidence belongs to the feature PR. This is not SSDP discovery, a physical TV compatibility result, a decoder test or a security audit.


## Native DLNA read-only position snapshot (P4, #104)

The native manual DLNA view adds an explicit GetPositionInfo request and a strict bounded SOAP RelTime/TrackDuration parser. No automatic polling, seek, persistence, SSDP or extra destination is introduced. Positive/negative Swift smoke, owned loopback transport, Python fixture and production iPhone/iPad XCUI are part of the new slice; only final-head successful CI constitutes automated acceptance. Real TV/Apple hardware and signed release remain unverified; parent #5 stays open.

## 2026-10-30 native manual DLNA bounded seek (#106)

A new iPhone/iPad explicit ±15-second REL_TIME seek subset uses fresh AVTransport GetTransportInfo/GetPositionInfo and strict finite-duration clamping before a private-LAN SOAP Seek. The owned fixture and positive/negative Swift/Python/XCTest/XCUI regressions are tracked in the feature PR; only a successful final-head full gate permits merging/closing the implementation issue. SSDP, real renderer models, SMB, independent security review, physical Apple devices and signed distribution remain unverified. P4 #5 and P2–P6 remain open.

## Native DLNA explicit pause/resume control (P4, #108)

A native SwiftUI **继续播放** button is enabled only after an acknowledged pause or a fresh user-requested PAUSED_PLAYBACK state. A second fresh GetTransportInfo immediately precedes Play(Speed=1), rejecting stopped, already-playing and unsupported states. Renderer/media edits and failures clear the local paused state. The owned loopback SOAP fixture is exercised by positive/negative Swift network smoke, XCTest and production iPhone/iPad XCUI. This is pending final-HEAD integration CI, and does not establish actual TV/Apple device support, SSDP, SMB or release readiness.


## Native DLNA absolute time seek (P4, #110)

A native SwiftUI HH:MM:SS field and explicit seek action extend the manually configured private-LAN AVTransport subset. Input is strictly ASCII and validated before network access; the action checks fresh renderer state and finite media duration and rejects targets beyond the reported duration. Owned fixture, positive/negative Swift smoke/XCTest, network and production iPhone/iPad XCUI are part of the PR; final-head full CI remains required. No SSDP, real renderer compatibility, SMB, physical device acceptance or signed distribution is implied.

## Native opt-in DLNA device-description import (P4, #112)

The manual iOS DLNA page now accepts an explicitly supplied private-LAN UPnP device-description URL and imports its unique, same-origin AVTransport:1 control endpoint after a bounded GET and strict XML validation. No SSDP, multicast discovery, automatic playback, credentials, URLBase trust or additional server endpoint. Positive/negative Swift smoke, localhost network, XCTest, production SwiftUI XCUI and final-head CI are required before implementation acceptance. Real TV/iPhone/iPad, broader UPnP compatibility, SMB, independent security review and signing are not claimed.

## Native SSDP response parser prerequisite (P4, #114)

A pure Swift, non-networking parser now screens bounded SSDP M-SEARCH HTTPU response datagrams and sender-matched private IPv4 LOCATION candidates before any future UPnP device-description fetch. Adversarial Swift smoke/XCTest cases cover forged origin, duplicate headers, unsupported targets, malformed line endings, trailing bodies and size limits. This is not a multicast implementation or a user-visible discovery feature. Final-head iPhone/iPad simulator and aggregate CI must pass before accepting the parser increment. SSDP M-SEARCH transport, Apple multicast entitlement/provisioning, actual iPhone/iPad and renderer tests remain open under #114 and parent #5.

## Native optional UPnP renderer friendlyName (P4, #116)

An explicit native DLNA device-description import now returns a bounded, display-only friendly name alongside the previously validated same-origin AVTransport control URL. Names are optional, not trusted as device identity, and neither persisted nor used as authorization. Malformed/duplicate/nested/foreign/oversized/control/bidi names are rejected; owned Swift smoke/XCTest/XCUI and loopback fixtures are required, with final-head full CI before merging. SSDP transport/entitlement, real renderer interoperability, SMB, Apple hardware acceptance and P6 release remain open.

## Native WebDAV bounded last-modified display (P4, #119)

The iPhone/iPad read-only Depth:1 PROPFIND now requests optional `DAV:getlastmodified` and displays validated RFC 1123 GMT timestamps in the SwiftUI listing. The parser accepts only direct DAV properties in successful propstat; duplicate, conflicting, nested, foreign, failed, malformed and oversized values become unknown rather than blocking file access. The existing 1 MiB XML, 200-entry, credential-scope and no-redirect limits remain unchanged. Owned fixture, Swift positive/negative smoke, network, XCTest and iPhone/iPad XCUI are part of the PR; final-head aggregate CI must pass before merge. No external provider, physical Apple device, SMB, independent security audit or release validation is claimed.

## Native UPnP optional renderer modelName (P4, #118)

The explicit, user-entered LAN description import parses one bounded optional direct `root/device/modelName` and displays it in native SwiftUI beside the approved control URL and optional friendly name. Empty/missing is valid; duplicate, nested, foreign, control/bidi or oversized model names fail closed. Model data is display-only and never persisted or used for endpoint trust. Owned Python loopback, Swift parser/network smoke, XCTest and production iPhone/iPad XCUI are required; final-head full CI is pending before merge. This does not establish SSDP multicast discovery, SMB, physical Apple/TV interoperability, legal Spider corpus, independent security audit or signed release.
