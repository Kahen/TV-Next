# Native iPhone/iPad audio track selection (P4 partial)

The SwiftUI player exposes a **per-item** audio-track menu when AVFoundation reports an `AVMediaSelectionGroup` for the audible characteristic. Labels are bounded and numbered to distinguish duplicate languages. The selected option is applied directly to the current `AVPlayerItem` without replacing the item or losing playback progress.

The list is limited to the first 16 options. Unsupported codecs, containers with no selectable group, external audio files, system-managed routes and DRM-specific track handling are **not** made compatible by this menu. A missing menu means AVFoundation did not expose selectable audio tracks; it does not mean the source has no audio. Audio preferences are intentionally not persisted, synced or sent to the server. New playback items, retry and clearing the library invalidate old track choices and asynchronous discovery results.

## Automated acceptance

The iOS CI creates a source-free 4-second MP4 with two synthetic sine-wave AAC tracks using FFmpeg, then regenerates the Xcode project so XCTest can load the fixture. `MediaLibraryTests.testAudioTrackSelectionIsItemScopedAndRejectsInvalidIndices` covers discovery, selection, negative/out-of-range indices, switching items and clearing the library. The same workflow builds the production SwiftUI app and runs XCTest/XCUI on iPhone/iPad simulators.

These checks do **not** establish physical Apple codec compatibility, audio quality, energy use, AirPlay route behavior or accessibility validation with VoiceOver. Record those separately in #38. No signed IPA/Release is produced.
