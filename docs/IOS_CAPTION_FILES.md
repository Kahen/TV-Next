# Native Files/SMB subtitle import (P4, #134)

## User-visible path

In **本机文件与字幕**, select **导入 SRT / VTT / ASS / SSA 字幕**. The system Files picker can open a provider document, including a user-authorized SMB share connected through the iOS Files app. TV-Next reads the selected subtitle in the background and applies parsed cues to the current AVPlayer overlay. The selected provider path, SMB credentials and caption contents are not stored in the media library, synced or uploaded. This is not a native SMB client or a guarantee of provider compatibility.

The import button is disabled while the read is in progress. **取消字幕导入** cancels the worker and invalidates its completion; changing playback, selecting a newer subscription subtitle, clearing the library, removing captions, backgrounding the app or leaving the view also invalidates the read. A failed or cancelled import retains the existing cues rather than replacing them with partial data. Only actual user cancellation is silent; Files picker/provider errors are shown to the user. Only a successful, still-current result replaces captions and resets the offset.

## Safety and resource limits

- Only user-selected **file:** URLs with SRT/VTT/ASS/SSA extensions are eligible. Directories and other formats are rejected; no scripts, plugins or remote URLs execute.
- A detached worker obtains security-scoped access and, on Apple platforms, performs a coordinated read using NSFileCoordinator. No blocking Files hydration is performed on the main SwiftUI actor.
- The reader checks the provider's declared length when available, then reads in 64 KiB chunks with a strict **1,048,576-byte** actual-data cap (including an extra-byte check at the limit). UTF-8 (with or without BOM) and explicitly BOM-marked UTF-16LE/UTF-16BE are supported. BOM-only, odd-byte, malformed-surrogate, empty, unsupported legacy encoding and invalid-timeline inputs are rejected by CaptionParser; BOM-less UTF-16 is not guessed.
- Cancellation is checked between reads and before parsing; NSFileCoordinator itself may not stop immediately while a provider is hydrating, but stale completion cannot change playback state. The worker does not create persistent temporary files.
- The existing text-only parser strips markup and does not support styled ASS positioning, WebVTT layout or DRM/codec conversion.

## Automated and physical acceptance

Positive and negative Swift smoke/XCTest cover SRT/VTT, exact byte limit, oversized sparse files, empty/invalid-encoding input, unsupported extensions, directories, pre-cancellation and picker cancellation versus provider errors. Production SwiftUI XCUI checks the native entry's idle state on both iPhone and iPad simulators; the full final-HEAD integration gate also runs Web/API, PostgreSQL, Compose, NAS and Spider isolation.

**Simulator and local file fixtures do not prove an actual SMB File Provider works on a physical iPhone/iPad.** Verify authentication, provider hydration, cancellation, errors and playback overlay against a permitted NAS share on both device families as a separate physical acceptance item. Parent P4 #5 and P6 #7 remain open. No Apple signing, TestFlight, IPA or release is implied.

## UTF-16 subtitle compatibility increment (#136)

The same bounded Files/SMB import path now decodes explicitly BOM-marked UTF-16LE and UTF-16BE SRT/VTT/ASS/SSA as text, including Chinese subtitles. This is a parser change only; it does not increase the 1 MiB raw-byte limit, add GBK/GB18030 heuristics, change File Provider hydration, or imply real NAS verification. Swift smoke, Files smoke, XCTest and the full iPhone/iPad simulator gate must pass on the final PR head before merge.
