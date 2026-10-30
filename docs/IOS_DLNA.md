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
