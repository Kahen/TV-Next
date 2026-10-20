# Compatibility matrix

Legend: Implemented = available in current code; Planned = not implemented; Experimental = only known subset verified.

| Feature | Web | iOS/iPadOS | Server |
|---|---|---|---|
| MP4 progressive HTTP playback | Planned P0 | Planned P0 | Not required |
| HLS playback | Planned P0 (native/MSE) | Planned P0 (AVPlayer) | Not required |
| M3U metadata import | Planned P0 | Planned P1 | Planned P0 |
| FongMi JSON inspection | Planned P0 | Planned P1 | Planned P0 |
| FongMi sites/home/search/details | Planned P2 | Planned P2 | Planned P2 |
| Java/JAR Spider | N/A | N/A | Planned P3 (pure JVM subset) |
| JS Spider | N/A | N/A | Planned P3 |
| Python Spider | N/A | N/A | Planned P3 |
| Android-context/JNI Spider | Unsupported until separately assessed | Unsupported until separately assessed | Unverified |
| EPG/XMLTV | Planned P2 | Planned P2 | Planned P2 |
| ASS subtitles/danmaku | Planned P4 | Planned P4 | Depends on assets |
| AirPlay | N/A | Planned P4 | N/A |
| DLNA | Browser restricted | Planned P4 | Planned P4 |
| SMB/WebDAV | Browser restricted | Planned P4 | Planned P4 |
| Native background playback | Browser limited | Planned P4 | N/A |
| Transcoding | N/A | N/A | Planned P4 (sidecar) |

The word "Planned" indicates work remains to be implemented. Update rows only after tests, especially on real devices.
