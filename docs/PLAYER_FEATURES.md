# Player feature guide (P1)

## Local media on Web

Use the "从本机播放视频 / 音频" picker for authorized files. A temporary browser object URL is created; file bytes are not uploaded. Switching media or leaving the page releases the URL. Local media is not added to saved streams or history. Supported codecs vary by browser; local MKV and HLS manifests with relative segments are not supported by this feature.

## SRT and WebVTT subtitles

Choose a UTF-8 SRT/VTT file under 1 MiB while a video is selected. Common SRT time cues are converted into a browser WebVTT text track. Rich styling, ASS/SSA, legacy encodings and automatic language selection remain unsupported. A local -10 to +10 second subtitle timing offset is available on Web and iOS (positive values delay the captions); it does not change actual media time.

## Fullscreen and picture-in-picture

Controls use the browser's user-gesture APIs and display errors when unavailable. iOS Safari and other browsers can require native video controls or not support these methods. Passing Web CI does not prove physical-device playback.

## PWA shell (not offline streaming)

The manifest and SVG icon support PWA installation groundwork. A service worker registers only in production, with static shell and compiled JS/CSS caching; API endpoints, source URLs, videos and HLS segments are never cached. Offline stream playback or browsing is NOT implemented. Browser installability may need PNG icons and platform-specific testing.

## Playlist export (Web / iOS)

Use "导出 M3U" on Web or "导出当前播放列表 (.m3u)" on iOS to export current channels. Exports contain their original URL and potentially sensitive query tokens. They do not include favorites, history or saved positions.

## iOS playback speed

Native AVPlayer speed controls provide 0.75x, 1x, 1.25x, 1.5x and 2x. Some streams cannot change rate. Actual-device and App Store distribution testing remain pending.

## Out of scope

Real Spider execution, full FongMi parity, embedded/multiple native subtitle tracks, ASS styling, AirPlay, DLNA, PWA offline media, transcoding, DRM circumvention and signed IPA releases remain future work.

## iOS local Files media and external captions

Files picker accepts an item only if its extension is one of MP4, M4V, MOV, MP3, M4A or AAC. After checking the 2 GiB upper bound, the app copies it into a private temporary cache before playback with AVPlayer, avoiding reliance on long-lived Files security scope permissions. The content is never uploaded or put into the persistent media library. Playback may fail for unsupported codecs or insufficient local storage.

An external UTF-8 SRT/VTT file smaller than 1 MiB is parsed on-device into bounded, text-only cues and displayed with a SwiftUI overlay synchronized to the AVPlayer timeline. It is not an embedded/selected native AVPlayer subtitle track; multiple simultaneous subtitles, positioning, ASS styling and timing adjustment are not included.

Native simulator compilation and caption fixtures do not prove that a specific iPhone/iPad decodes any arbitrary video. Physical-device tests are mandatory before an Apple distribution milestone.

## P4 external-caption synchronization

Both Web and iOS offer an external-caption offset slider from **-10 to +10 seconds** in 0.5-second steps. Positive means captions appear later, negative means earlier. The Web client regenerates an ephemeral WebVTT text-track URL from the original source text, without accumulating offsets; iOS evaluates cue timing against the AVPlayer clock using the offset. Changing videos or importing new subtitles resets the offset. Automated TypeScript and Swift boundary tests cover positive/negative offset, zero and out-of-range inputs. This is **text cue synchronization**, not ASS/SSA, embedded track switching or proven real-device playback.
