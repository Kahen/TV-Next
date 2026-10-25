# Player feature guide (P1)

## Local media on Web

Use the "从本机播放视频 / 音频" picker for authorized files. A temporary browser object URL is created; file bytes are not uploaded. Switching media or leaving the page releases the URL. Local media is not added to saved streams or history. Supported codecs vary by browser; local MKV and HLS manifests with relative segments are not supported by this feature.

## SRT, WebVTT and text-only ASS/SSA subtitles

Choose a UTF-8 SRT/VTT/ASS/SSA file under 1 MiB while a video is selected. Common SRT and ASS/SSA `[Events]` `Format`/`Dialogue` time cues are converted to a browser WebVTT track, including commas in the final `Text` field, `\\N` line breaks and stripped overrides. Native iOS renders equivalent bounded text cues. ASS/SSA positioning, styles, fonts, animation and karaoke effects, legacy encodings and automatic language selection remain unsupported. A local -10 to +10 second subtitle timing offset is available on Web and iOS (positive values delay the captions); it does not change actual media time.

## Fullscreen and picture-in-picture

Controls use the browser's user-gesture APIs and display errors when unavailable. iOS Safari and other browsers can require native video controls or not support these methods. Passing Web CI does not prove physical-device playback.

## PWA shell (not offline streaming)

The manifest and SVG icon support PWA installation groundwork. A service worker registers only in production, with static shell and compiled JS/CSS caching; API endpoints, source URLs, videos and HLS segments are never cached. Offline stream playback or browsing is NOT implemented. Deterministic 192/512 PNG icons and a 180 PNG Apple touch icon are generated before each production build. Offline shell reload is browser-tested; installed behavior and prompts still need platform testing (#38).

## Playlist export (Web / iOS)

Use "导出 M3U" on Web or "导出当前播放列表 (.m3u)" on iOS to export current channels. Exports contain their original URL and potentially sensitive query tokens. They do not include favorites, history or saved positions.

## iOS playback speed

Native AVPlayer speed controls provide 0.75x, 1x, 1.25x, 1.5x and 2x. Some streams cannot change rate. Actual-device and App Store distribution testing remain pending.

## Out of scope

Real Spider execution, full FongMi parity, embedded/multiple native subtitle tracks, styled ASS rendering, AirPlay, DLNA, PWA offline media, transcoding, DRM circumvention and signed IPA releases remain future work.

## iOS local Files media and external captions

Files picker accepts an item only if its extension is one of MP4, M4V, MOV, MP3, M4A or AAC. After checking the 2 GiB upper bound, the app copies it into a private temporary cache before playback with AVPlayer, avoiding reliance on long-lived Files security scope permissions. The content is never uploaded or put into the persistent media library. Playback may fail for unsupported codecs or insufficient local storage.

An external UTF-8 SRT/VTT/ASS/SSA file smaller than 1 MiB is parsed on-device into bounded, text-only cues and displayed with a SwiftUI overlay synchronized to the AVPlayer timeline. It is not an embedded/selected native AVPlayer subtitle track; multiple simultaneous subtitles, positioning and ASS styling are not included. The external-caption timing offset is described below.

Native simulator compilation and caption fixtures do not prove that a specific iPhone/iPad decodes any arbitrary video. Physical-device tests are mandatory before an Apple distribution milestone.

## P4 external-caption synchronization

Both Web and iOS offer an external-caption offset slider from **-10 to +10 seconds** in 0.5-second steps. Positive means captions appear later, negative means earlier. The Web client regenerates an ephemeral WebVTT text-track URL from the original source text, without accumulating offsets; iOS evaluates cue timing against the AVPlayer clock using the offset. Changing videos or importing new subtitles resets the offset. Automated TypeScript and Swift boundary tests cover positive/negative offset, zero and out-of-range inputs. This is **text cue synchronization**, including basic ASS/SSA Dialogue text but not rich ASS styling, embedded track switching or proven real-device playback.

## Native P1 navigation and lifecycle

Use the “功能导航” toolbar menu to jump to the player, quick URL, Files/subtitles, playlist import, JSON preview or library. Library collection menus and labeled 44-point favorite buttons support large Dynamic Type. “全屏播放” retains the current AVPlayer and subtitle/danmaku state, with an explicit exit control and portrait/landscape support. Native item failures show a retry control. Backgrounding saves finite-VOD progress and pauses; returning does not automatically resume audio. Automatic native PiP/background media/AirPlay are P4 work.

Web pagehide/hidden events synchronously save the latest finite-VOD position before unload. PWA cache includes only static application resources, never API responses, source URLs or media. See [P1_IMPLEMENTATION.md](P1_IMPLEMENTATION.md) for automated evidence and [#38](https://github.com/Kahen/TV-Next/issues/38) for deferred physical acceptance.
