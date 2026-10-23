# Compatibility matrix

Legend: Implemented = coded and checked at compile/test level (NOT necessarily device-tested); Planned = not implemented; Experimental = only a known subset verified.

| Feature | Web | iOS/iPadOS | Server |
|---|---|---|---|
| MP4 progressive HTTP playback | Implemented UI (browser/device test pending) | Implemented AVPlayer UI (device test pending) | Not required |
| HLS playback | Implemented via native/MSE/HLS.js (source/CORS dependent) | Implemented AVPlayer (device test pending) | Not required |
| M3U metadata import | Implemented via API | Implemented offline or via API | Implemented bounded subset |
| FongMi JSON inspection | Implemented (static only) | Offline file/paste metadata preview (iOS simulator CI; real device pending) | Implemented (static only) |
| Local file play | Implemented via ephemeral blob URL (codec-dependent) | Files -> staged private cache -> AVPlayer (device test pending, 2 GiB max) | N/A |
| UTF-8 SRT/WebVTT subtitles and offset | Text track with -10..+10s generated WebVTT cue adjustment | SwiftUI caption overlay with AVPlayer-aligned -10..+10s shift (device test pending) | N/A |
| Fullscreen / Picture-in-Picture | Browser API best effort | Native verification pending | N/A |
| PWA groundwork | Manifest, SVG icon, static shell SW | N/A (native app) | N/A |
| M3U export | Implemented | FileDocument implemented (Files verification pending) | N/A |
| Playback speed | Implemented | AVPlayer rate selector (device test pending) | N/A |
| Favorites, recents and VOD resume | Implemented locally (unit tests) | Implemented locally (simulator build test) | Not required |
| Cross-device library synchronization | Planned P5 | Planned P5 | Planned P5 |
| FongMi JSON site metadata preview | Implemented (metadata only, no Spider) | Offline metadata only (device test pending) | Implemented bounded parser |
| FongMi IPTV groups/channels | Preview + manual click for plain HTTP(S) URLs | Planned | Implemented bounded metadata parser |
| Static FongMi Result home/category/search/details/episodes | Web offline JSON browsing + direct HTTP(S) play | Native offline JSON browsing + direct AVPlayer URLs (simulator tests pending) | Static result normalization and MockMvc golden tests |
| Real FongMi sites/home/search/details | Planned P2 | Planned P2 | Planned P2 |
| Java/JAR Spider | N/A | N/A | Bundled Java 21 `ProviderSpi` fixture in Docker; static JAR compatibility inspection; third-party JAR execution not supported |
| JS Spider | N/A | N/A | Bundled JS fixture worker in Docker (no dynamic Spider compatibility) |
| Python Spider | N/A | N/A | Bundled Python fixture worker in Docker (no dynamic Spider compatibility) |
| Android-context/JNI Spider | Unsupported until separately assessed | Unsupported until separately assessed | Unverified |
| EPG/XMLTV | Manual local XMLTV import + current/upcoming programme matching (not auto refresh) | Planned | XXE-safe SAX parser, timezones, bounded matching |
| ASS subtitles/danmaku | Planned P4 | Planned P4 | Depends on assets |
| AirPlay | N/A | Planned P4 | N/A |
| DLNA | Browser restricted | Planned P4 | Planned P4 |
| SMB/WebDAV | Browser restricted | Planned P4 | Planned P4 |
| Native background playback | Browser limited | Planned P4 | N/A |
| Transcoding | N/A | N/A | Planned P4 (sidecar) |

Native JSON preview covers only site metadata and live declaration counts; it does not reproduce Web's live-channel catalog or provider execution. See docs/IOS_CONFIG_PREVIEW.md.

"Implemented" does not imply 100% source compatibility. Device-specific playback has not yet been validated on a physical iPhone/iPad. See docs/LOCAL_LIBRARY.md.
