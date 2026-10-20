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
