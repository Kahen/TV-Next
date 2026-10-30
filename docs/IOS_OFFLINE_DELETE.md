# Native iOS offline deletion safety (P4, #83)

The iPhone/iPad offline media section lists completed local copies and their
aggregate on-disk bytes against the existing 20-file / 2 GiB limits. It only
supports direct user-authorized HTTP(S) MP4/M4V/MOV/MP3/M4A/AAC downloads;
the underlying transfer retains its 512 MiB per-file cap, Wi-Fi-only request,
redirect refusal, media-header checks and ephemeral credential policy.

Tapping **删除：<名称>** now opens a destructive confirmation. **取消** keeps the
catalog entry, local file and any active AVPlayer item unchanged. Only the
explicit **删除离线文件** action releases that file from AVPlayer (if currently
playing) and removes the catalog entry and app-owned file. It does not stop
unrelated playback. A deletion cannot be undone; the UI states this before
confirmation.

The production iPhone/iPad XCUI test downloads a locally owned fixture,
relaunches the app, plays the saved copy, cancels deletion and checks that
playback and the copy remain, then confirms deletion and verifies that the
copy disappears and playback is released. The test also checks the visible
storage-usage indicator. This is an automated simulator scenario, not a
claim of physical-device, third-party provider, DRM, HLS or signing support.

This slice changes no source, credential or URL persistence; the offline
catalog continues to store only generated file IDs, display names,
extensions and byte counts. The feature issue closes only after the final
PR HEAD passes all required CI checks. Physical-device acceptance remains
separate in #38.

## iPhone alert-dismissal regression (2026-10-31)

The final-head #109 integration gate (run [41093070709](https://github.com/Kahen/TV-Next/actions/runs/41093070709)) reported an iPhone-only XCUI failure after tapping **删除离线文件**: the catalog entry was still visible, while the iPad gate passed. The old SwiftUI `isPresented` binding could clear `pendingDeletion` during dismissal before the destructive action read it; a nil guard would silently skip deletion. The action now receives the immutable entry captured by SwiftUI's `alert(isPresented:presenting:)` overload, so dismissal ordering cannot erase the selected target. Cancellation still does not remove files or stop playback.

The existing production XCUI scenario retains both negative (cancel keeps copy and active player) and positive (confirmed deletion removes copy and releases active player) assertions. It now waits up to five seconds for SwiftUI's accessibility tree to reflect the synchronous catalog mutation, rather than assuming immediate reconciliation. This is a code-level diagnosis and regression fix, **not** a claim that the new HEAD passed iPhone/iPad tests until the new full integration run succeeds.
