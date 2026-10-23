# TV-Next for iPhone and iPad

Universal SwiftUI native client with AVKit/AVPlayer. Development requires macOS + Xcode 16+ and XcodeGen.

1. Install XcodeGen (for example, brew install xcodegen).
2. In apps/ios run xcodegen generate.
3. Open TVNext.xcodeproj in Xcode and run the TVNext scheme on an iOS 17+ simulator.
4. Paste M3U text or choose a local M3U/TXT file through Files; **offline parsing is the default and requires no API**.
5. Optionally enable the API parser and set the API URL (localhost works in the simulator; real devices need a reachable trusted server, preferably HTTPS).
6. Play authorized MP4 or HLS links, save favorites and recents, resume finite-length videos. AVPlayer codec and ATS limitations apply.
7. Channel lists (up to 1500), favorites, recents and VOD progress are stored locally in UserDefaults. They are **not synced** to Web or other Apple devices.

Smoke parser tests run in iOS CI on macOS using Swift; iOS simulator builds are unsigned. Test on physical devices before distribution.

This is an early native UI, not an iOS execution environment for Android JAR, AAR or Spider plugins. The full features are scoped in docs/ROADMAP.md.

## P1 playback controls and export

- The player includes a 0.75x to 2x native rate selector, subject to AVPlayer stream capabilities.
- After importing a playlist, use the "导出当前播放列表 (.m3u)" button to choose a destination in Files.
- M3U exports include full stream URLs, including sensitive query tokens. Do not publish exported files.
- Media is still played by native AVPlayer, not by executing Android or Spider plugins.
- Real-device playback, Files export, subtitle and background playback verification are still pending.

## Local media and subtitles (P1)

- Choose **打开本地视频 / 音频** and select an authorized MP4, M4V, MOV, MP3, M4A or AAC file from Files. The app copies a file of at most **2 GiB** to its private cache, because a document-picker security-scoped URL may not stay valid during playback. Importing large files uses space and may take time.
- A local file is never uploaded to the backend, added to favorites or recent streams, or restored automatically after relaunch. The previous staged file is deleted when a new source replaces it or when the player is cleared. An unexpected termination may leave a temporary cache file until iOS reclaims the cache.
- Select **导入 SRT / WebVTT 字幕** for UTF-8 plain-text captions up to **1 MiB**. Cues are rendered in a SwiftUI overlay aligned with AVPlayer's current time, not as a system-selectable AVMediaSelection track.
- Captions support common SRT/WebVTT cues, simple text and basic timestamps. No ASS/SSA, advanced WebVTT positioning, styling, offsets, muxed subtitle track selection or translation yet.
- Playback of a supported filename still depends on codecs provided by iOS/AVPlayer. Media copied from cloud storage can fail when inaccessible, oversized, or low on available device storage. Test on physical iPhone/iPad before distribution.

## Native offline FongMi Result catalogue (P2 subset)

Paste a **FongMi Result** JSON (`class` + `list`) or select a local UTF-8 JSON file in the new **影视目录** section. The native iOS implementation parses and filters locally; browse up to 200 categories/2,000 items, search by title, see detail/playback lines and episodes, then tap a supported direct HTTP(S) URL to play with AVPlayer.

This feature never requests Spider URLs, downloads external configs or artwork, executes plugins, or sends JSON to the server. Playback URL validation reuses the existing M3U URL policy, so script schemes and credentials in URLs are rejected. Metadata is not persisted. It cannot resolve `csp_*` Spider sites or complex episode parsing yet.

A shared synthetic [golden Result](../../fixtures/p2-fongmi-result.json) is exercised by native Swift parser smoke tests and Spring MockMvc API integration tests. This ensures consistency for the tested subset but is not proof of real provider compatibility or physical Apple device playback.
