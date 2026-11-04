# Compatibility matrix — 2026-11-04

“Implemented subset” means source and owned-fixture automation exist. It does not mean every provider, codec or physical Apple device is supported. Current source inventory and exact automated evidence: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). P1 physical/installed-PWA acceptance remains [#38](https://github.com/Kahen/TV-Next/issues/38); P2–P6 remain open.

| Feature | Web/PWA | iPhone/iPad | Server/runtime |
| --- | --- | --- | --- |
| MP4/HLS and local media | Browser native/MSE/hls.js; CORS/codec dependent; ephemeral local blob | AVPlayer; coordinated Files import into bounded private staging cache | Optional authenticated HTTP/HLS relay |
| Favorites/history/resume/import/export | Implemented subset | Implemented subset | Opt-in account-scoped revision-CAS library sync |
| Fullscreen/PiP/speed | Browser APIs with unsupported feedback | Native fullscreen, AVKit PiP and rate selection | N/A |
| Background/AirPlay | Browser/platform dependent | Opt-in background audio, system controls and AirPlay route picker; physical behavior pending | N/A |
| PWA offline | Installed shell/static resources only; no offline streaming | Native app | No API/media service-worker cache |
| FongMi subscriptions/catalogs | Type 0/1/2/4 home/category/filters/search/detail/episodes/lines | Same protocol subset; optional subscription URL in device-only Keychain | Bounded source-derived decoding/HTTP provider operations; not arbitrary Spider execution |
| Cross-site search | Bounded concurrent search, cancellation and partial failure | Additionally failed-only retry preserving original query/provider boundary, clipping and empty-result feedback | Per-device provider health/search cache |
| Live and XMLTV | M3U/TXT/JSON live channels, guide/feeds and bounded replay | Native live/guide/feed/replay controls | XXE-safe bounded XMLTV/XMLTV.gz feeds, scheduler/cache and replay resolution |
| Audio/embedded subtitles | Platform-native controls; explicit per-title preference parity remains | AVPlayer track/off selection, unique full-identity preferences and per-title forget | N/A |
| External SRT/VTT/ASS/SSA | Text-only cues with -10..+10 s offset | Text overlay, up to four overlapping cues; Files UTF-8/UTF-16 and explicit GB18030; subscription captions | Bounded subscription text-resource retrieval |
| Styled ASS/fonts/karaoke | Not implemented | Not implemented; external overlays are not composited into system PiP | N/A |
| Danmaku | Bounded parser/timeline overlay and settings | Bounded XML/JSON parser/overlay, persisted display settings and nested-XML ownership regression | Subscription resource retrieval |
| Intro/outro | No equivalent saved-marker feature | Manual per-title markers with opt-in automatic skipping; no detection/provider metadata | N/A |
| Playback diagnostics | Browser error reporting | Private codec/dimensions/audio/buffer/timeline/error metadata; actual hardware-decoder selection not exposed | Private diagnostics/metrics |
| AList/OpenList | Read-only listing/folder/media selection | Read-only listing/folder/media selection | Bounded adapter/opaque IDs; no direct cloud QR/OAuth login |
| WebDAV | No dedicated client | Bounded read-only Depth:1, root/parent/refresh/filter/sort, size/date metadata; in-memory HTTPS Basic credentials | Existing authenticated relay used for protected media |
| DLNA | No dedicated controller | Manual private-LAN AVTransport/UPnP-description subset: play/pause/resume/stop/state/position/seek; physical renderer matrix pending | No renderer discovery service |
| SSDP discovery | Not implemented | Dormant parser/UDP/resolver with owned fixtures; production UI stays manual pending multicast entitlement/provisioning/discovery UI/device verification | N/A |
| SMB | No dedicated client | User-selected media/caption import from shares connected in Apple Files; no native directory browser or direct remote streaming | No SMB adapter |
| Offline media | Shell only | Foreground direct unauthenticated files, persistent completed copies and deletion; no HLS/DRM/background/resume | No offline/transcoding job service |
| Java/JAR Spider | Never executed in client | Never executed in client | Actual owned pure-JVM JAR loader with original media signatures in OS sandbox; external registry/dispatcher/corpus/egress remain pending |
| JS/QuickJS/Python Spider | Never executed in client | Never executed in client | Bundled Node/Python fixture workers only; real adapters/dependencies remain pending |
| Android DEX/JNI Spider | Optional bridge capability UI | Optional bridge capability UI | Administrator-bound separate Android host bridge; actual ARM plugin/media validation pending |
| Accounts/remote/sync | Pairing and opt-in sync/remote controls | Pairing and opt-in sync/remote controls | Hashed device tokens/revocation, ACL, WebSocket tickets, bounded relay; real remote-NAS review pending |
| Transcoding | Not implemented | Not implemented | Resource-limited sidecar remains planned |
| Distribution | Unsigned candidate build | Unsigned simulator tests; no signed IPA/TestFlight acceptance | Linux amd64 candidate images/JAR, source/checksums/SBOM and host/Docker JAR equality; no full signed release claim |

For original Android semantics and exact references, see [UPSTREAM_COMPATIBILITY.md](UPSTREAM_COMPATIBILITY.md), [LIVE_REPLAY.md](LIVE_REPLAY.md) and [PURE_JVM_SPIDER.md](PURE_JVM_SPIDER.md). Importing a subscription or passing an owned fixture is not proof that its external Spider/streams execute successfully.
