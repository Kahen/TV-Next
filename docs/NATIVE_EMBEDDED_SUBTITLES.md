# Native embedded/HLS subtitle selection (P4 partial)

Parent #5; implementation subtask #55. The original FongMi/TV subtitle settings UI (pinned source `123cc086159b0f13bf54bdf64bacbc259ca47c88`, `app/src/main/java/com/fongmi/android/tv/ui/dialog/SubtitleSettingPanel.java`) uses Android Media3 track selection. TV-Next implements only the corresponding **native Apple AVFoundation** media-selection subset; it does not port Media3, Android styling, dual subtitles, custom fonts or karaoke rendering.

The SwiftUI player exposes up to 16 `AVMediaSelectionGroup` options for the `.legible` characteristic on the installed `AVPlayerItem`. Selecting an option asks AVFoundation to render the embedded/HLS subtitle track. An explicit **off** option is shown only when `allowsEmptySelection` is true. Unsupported containers, codec-specific subtitles and media without a legible group continue playback without this menu. Existing imported SRT/VTT/ASS-text overlays remain separate and can coexist; the app does not promise to suppress duplicate overlays automatically.

Selections are ephemeral: no subtitle track IDs, private media URLs or preferences are saved or synced. Replacement, retry, clear and asynchronous cancellation invalidate stale track discovery/selection. Switching tracks does not replace the player item or reset playback progress.

## Synthetic automated verification

The iPhone/iPad simulator workflow serves a local FFmpeg-generated 4-second HLS fixture with two synthetic AAC renditions and a synthetic WebVTT subtitle rendition declared through `EXT-X-MEDIA:TYPE=SUBTITLES`. XCTest checks discovery, valid selection, explicit off, invalid indices, stale-item rejection and reset on local-file switch and clear. The full cross-platform gate must pass on the PR's final HEAD before merge.

No authorized external streams, physical-device codecs, VoiceOver, PiP/AirPlay subtitle rendering, native styled ASS/SSA or independent security review are claimed. Physical checks stay in #38. No signed IPA/Release is produced.
