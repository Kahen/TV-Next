# iPhone/iPad manual intro/outro markers (P4)

The original [FongMi PlayerManager](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/player/PlayerManager.java) exposes bounded player seeking. TV-Next adds **manual** per-title intro/outro markers on top of the existing AVPlayer finite-VOD seek path. This is **not** automatic intro detection, provider-supplied skip metadata, chapter parsing or Android Media3 parity.

## Native behavior

Open **播放器 → 手动片头 / 片尾标记**. During a ready remote finite video of at least 120 seconds, move the playhead and select **标记片头结束** (5–600 seconds and no later than the midpoint) or **标记片尾开始** (second half, at least 5 seconds before the end). Both may be set, with at least five seconds between markers. When the current time is before the saved intro boundary, **跳过片头** seeks there; after entering the saved outro segment, **跳过片尾** seeks to one second before EOF. Neither action occurs automatically. **清除标记** removes both for the selected title.

The app uses the same AVPlayer seek validation as system remote controls. Unknown-duration/live media, replay sessions, local sandbox files, unready items, invalid timestamps and videos shorter than two minutes are ineligible. The skip buttons do not change media when the playhead is outside the corresponding interval. The marker controls are disabled when no player item is installed; invalid operations provide local feedback.

## Persistence and privacy

Only an SHA-256 digest of the remote media URL, two numeric marker times and a numeric duration are stored in a versioned device-local UserDefaults snapshot. No raw URL, media request headers, Basic credentials, capability tickets or file paths are written. Storage is limited to 100 distinct titles and 64 KiB. Corrupt/unsupported snapshots are ignored. On reopening, a marker is used only when the duration still matches within max(2 seconds, 1%); a changed provider rendition therefore does not reuse an obviously stale boundary. AVPlayerItem can report an indefinite duration when its status first becomes ready. The native player observes later duration updates and retries restoration only for the still-installed, ready item; invalid durations do not erase the saved preference. Stale callbacks from replaced items cannot restore markers on a different title. Clearing the media library deletes the marker snapshot. This preference is never synchronized to the home server.

## Verification

- Linux Swift smoke (NativeIntroOutroMarkers.swift + IntroOutroSmoke.swift): local compile with warnings-as-errors passed for success, invalid times, wrong duration, unsafe key and deletion.
- XCTest: marker storage/reload, indefinite-to-finite duration retry, finite-boundary validation, duration mismatch and local-file exclusion. The delayed-duration regression has a deterministic storage test; actual KVO timing across external providers remains a physical-device acceptance item.
- XCUI: the production SwiftUI controls are present and disabled without media on iPhone/iPad simulators.
- **Merge gate:** final-HEAD full integration and native iPhone/iPad simulator checks must succeed. A local Swift smoke is not a simulator test.

Remaining: user-marked behavior on physical iPhone/iPad, actual provider streams, duration/seek accuracy, auto-skip or provider metadata support, SMB/DLNA and wider P4 acceptance. Physical testing remains in #38 and #5; do not publish a signed IPA or Release from this slice.
