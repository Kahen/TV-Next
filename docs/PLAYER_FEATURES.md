# Player feature guide (P1)

## Local media on Web

Use the "从本机播放视频 / 音频" picker for authorized files. A temporary browser object URL is created; file bytes are not uploaded. Switching media or leaving the page releases the URL. Local media is not added to saved streams or history. Supported codecs vary by browser; local MKV and HLS manifests with relative segments are not supported by this feature.

## SRT and WebVTT subtitles

Choose a UTF-8 SRT/VTT file under 1 MiB while a video is selected. Common SRT time cues are converted into a browser WebVTT text track. Rich styling, ASS/SSA, legacy encodings, delay/offset and automatic language selection are NOT yet supported.

## Fullscreen and picture-in-picture

Controls use the browser's user-gesture APIs and display errors when unavailable. iOS Safari and other browsers can require native video controls or not support these methods. Passing Web CI does not prove physical-device playback.

## PWA shell (not offline streaming)

The manifest and SVG icon support PWA installation groundwork. A service worker registers only in production, with static shell and compiled JS/CSS caching; API endpoints, source URLs, videos and HLS segments are never cached. Offline stream playback or browsing is NOT implemented. Browser installability may need PNG icons and platform-specific testing.

## Playlist export (Web / iOS)

Use "导出 M3U" on Web or "导出当前播放列表 (.m3u)" on iOS to export current channels. Exports contain their original URL and potentially sensitive query tokens. They do not include favorites, history or saved positions.

## iOS playback speed

Native AVPlayer speed controls provide 0.75x, 1x, 1.25x, 1.5x and 2x. Some streams cannot change rate. Actual-device and App Store distribution testing remain pending.

## Out of scope

Spider runtime, full FongMi parity, iOS local file play, iOS subtitle tracks, AirPlay, DLNA, PWA offline media, transcoding, DRM circumvention and signed IPA releases remain future work.
