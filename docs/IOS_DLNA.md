# Native iPhone/iPad manual DLNA AVTransport control (P4, #100)

## Source mapping and scope

Reference: [FongMi/TV mobile DLNACast.java](https://github.com/FongMi/TV/blob/fongmi/app/src/mobile/java/com/fongmi/android/tv/dlna/DLNACast.java). The original uses jUPnP to find a renderer's AVTransport service and sends SetAVTransportURI, Play and optional Seek. TV-Next's **initial native subset** implements **manual** AVTransport v1 SetAVTransportURI → Play, Pause and Stop. It does **not** implement SSDP/M-SEARCH discovery, device descriptions, automatic device selection, seek, DLNA metadata generation, remote subtitle injection, transcoding or provider-specific headers.

In the native **DLNA 投屏** section, enter the device's **actual AVTransport control URL** (not its device-description URL), for example http://192.168.1.20:1400/MediaRenderer/AVTransport/Control, and a direct HTTP(S) media URL the renderer can fetch independently. You can copy a current native channel's URL only when it does not require custom headers or replay resolution. A successful SOAP response means the command was acknowledged; it does **not** prove that the renderer decoded/played the media.

## Explicit safety and compatibility boundaries

- Renderer control URL must be an explicit IPv4 literal in 10/8, 172.16/12, 192.168/16 or loopback 127/8, use HTTP, have an explicit port and non-root path, and have no credentials, query, fragment or percent-encoded path. Hostnames, WAN endpoints, IPv6 and automatic discovery are deliberately excluded until a controlled LAN discovery implementation is tested.
- The app never persists the renderer URL or media URL in this section, and does not send them to the home API. It does send the supplied media URL to the selected renderer over **unencrypted LAN HTTP**, including any query tokens; use only a trusted LAN device. HTTP renderer control is not protected against LAN interception. Do not use an untrusted Wi-Fi network.
- Only direct HTTP(S) media URLs without embedded credentials/fragment are accepted. User-specific authorization headers, local files, replay sessions, private proxy headers and DRM cannot be forwarded. The renderer must support the media codec, URL and network route.
- Requests are opt-in, POST only, 8-second total deadline (including slow/trickled responses), cancellation synchronized with task creation, ephemeral session without cookies or configured proxies, no HTTP redirects, 32 KiB streaming response cap, and namespaced SOAP Envelope/Body/action-response verification. SOAP Fault, HTTP errors and malformed/oversized responses fail. All requests revalidate the private endpoint.
- iOS 17+ local-network permission/ATS behavior and device AVTransport compatibility require physical verification. No multicast entitlement, Apple signing, real TV, SMB or third-party provider compatibility is claimed.

## Automated verification

Run the Python fixture unit tests and Swift smoke tests from apps/ios. The macOS iOS workflow compiles NativeDLNA.swift with DLNASmoke.swift and DLNANetworkSmoke.swift, starts the owned loopback SOAP fixture on port 8768, and runs the Xcode native scheme on iPhone/iPad simulators. NativeDLNATests and production LibraryUITests cover SetURI, Play, Pause and Stop, including XML-escaped query parameters. Negative cases cover WAN/credential/encoded traversal endpoints, unsafe media, wrong SOAP action/namespace, HTTP 302/500, a 32 KiB + 1 response, pre-cancelled tasks and a slow-trickled response beyond eight seconds. The full integration gate must pass at the **final PR HEAD** before merge. Synthetic fixture success does not imply physical renderer interoperability.

## iPhone simulator regression and remediation (2026-10-30)

The initial final-head [full integration run #41005691395](https://github.com/Kahen/TV-Next/actions/runs/41005691395) passed Web/API, PostgreSQL, Compose, NAS, Spider isolation and iPad, but **failed iPhone XCUI**. The compact iPhone navigation Menu omitted its final “媒体库” action from the accessible, initially visible menu items. The existing production XCUI setup calls `jump("媒体库")` to clear local media before every test; therefore unrelated UI tests failed at setup, not at DLNA SOAP transport. The fix promotes “媒体库” to a dedicated, accessible top-bar shortcut instead of moving the truncation to another Menu item. The remaining 13 Menu actions and their production destinations are unchanged. The XCUI `jump("媒体库")` helper now exercises the real shortcut, while other destinations still exercise the Menu. The existing `LibraryUITests.setUp → clearLibraryIfNeeded → jump` path is the regression test on both simulator sizes. This is a UI reachability fix, **not** a relaxation of the test or a claim of successful revalidation. Merge requires the new HEAD's full iPhone/iPad XCTest/XCUI and aggregate gate to pass.

## Remaining work

SSDP discovery and device description parsing with network permission and multicast-entitlement assessment, real renderer models, DLNA URI metadata/DIDL-Lite compatibility, authenticated media relay for approved streams, seek and remote position, external subtitles, background behavior and physical iPhone/iPad tests remain P4/P5 tasks. Parent #5 stays open; release/signing gates remain P6.

## Read-only renderer playback state query (P4, #102)

The native **查询设备播放状态** button sends the standard AVTransport v1 `GetTransportInfo` action to the same manually approved LAN control endpoint. The app displays the **device-reported** `CurrentTransportState` separately from acknowledgements for SetURI/Play/Pause/Stop. A query can report STOPPED, PLAYING, PAUSED_PLAYBACK, TRANSITIONING, NO_MEDIA_PRESENT, RECORDING or PAUSED_RECORDING. Unknown, absent, duplicated, nested or foreign-namespace states are rejected rather than displayed as verified playback. A successful state query is not proof that the renderer decoded video or that the screen is showing the requested media.

The query uses the same explicit private IPv4 control URL, 8-second overall deadline, no redirects/cookies/proxy, 32 KiB streamed cap, cancellation and strict SOAP namespace validation as manual casting. No automatic SSDP discovery, background polling, credentials or URL persistence is added. A user may query an already-playing renderer; pause/stop become available only when its reported state permits playback control. An invalid/public endpoint leaves the query disabled.

Automated coverage: positive and negative Swift smoke/XCTest for exact state extraction, missing/unknown/duplicate/nested/foreign values and response limits; an owned stateful localhost SOAP fixture verifies Play → PAUSED_PLAYBACK → STOPPED; production SwiftUI XCUI exercises the real query button on both simulator families. Final-HEAD integration CI and physical renderer testing remain separate. No physical iPhone/iPad, real TV, SSDP, security audit or signed distribution is claimed.


## Read-only renderer position query (P4, #104)

The native **查询播放进度** button explicitly sends AVTransport v1 `GetPositionInfo` to the same user-approved private IPv4 control URL. It shows the renderer's reported `RelTime` and `TrackDuration`, without inferring playback, polling, seeking, persistence or new destinations. Only one direct, namespace-validated value of each is accepted. `HH:MM:SS` is bounded to 0–99 hours with minutes/seconds 0–59; `NOT_IMPLEMENTED` is accepted only for duration (display elapsed time alone). Missing, duplicate, nested, foreign-namespace, malformed, oversized, CDATA-spoofed, or position-greater-than-duration fields are rejected. The existing 8-second deadline, 32 KiB response cap, private IPv4 validation, redirect denial and cancellation remain in force.

Owned Python SOAP fixture, Swift positive/negative smoke, XCTest network/parser cases and production SwiftUI XCUI on both simulator families are required. Final-head full integration CI must pass before merging. This does **not** demonstrate SSDP discovery, seeking, actual TV interoperability, physical iPhone/iPad behavior, independent security review or signed distribution. Parent #5 stays open.

## Explicit bounded REL_TIME seek (P4, #106)

FongMi's original mobile `DLNACast.java` invokes jUPnP `Seek(SeekMode.REL_TIME, ...)` after Play when a start position exists. TV-Next's separate, explicit native **快退15秒 / 快进15秒** controls use AVTransport v1 `Seek` with `Unit=REL_TIME` and a canonical `HH:MM:SS` target. They first query **fresh** `GetTransportInfo` and `GetPositionInfo` on the same manually approved private IPv4 endpoint. Only PLAYING or PAUSED_PLAYBACK and a positive, known finite duration are accepted; targets clamp to [0, duration]. Unknown-duration/live media, STOPPED/TRANSITIONING/RECORDING states, invalid deltas, out-of-range times and malformed SOAP fail closed. No stored position, background polling, auto-seek or new network destinations.

Each bounded request retains the existing private-IP/port/path validation, no cookies/proxy/redirects, 8-second per-request deadline, 32 KiB response cap and cancellation. The three requests are not an atomic transaction: a real renderer can change media/state between queries. A successful Seek SOAP acknowledgement does not establish playback, timing accuracy or real-device interoperability. The app sends the user's chosen target only to the manually configured LAN device over unencrypted HTTP; do not use untrusted Wi-Fi.

Owned localhost stateful SOAP fixture and Python tests verify accepted Seek and stopped/invalid targets; Swift smoke/XCTest cover target bounds, 15-second clamping, missing duration, invalid deltas and full network flow. Production SwiftUI XCUI exercises an actual forward seek and a subsequent fresh position query on iPhone/iPad simulators. Final-HEAD complete integration CI is required before closing #106. Physical TV/iPhone/iPad, SSDP, SMB, security review and Apple signing remain separate; parent #5 stays open.
