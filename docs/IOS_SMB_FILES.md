# iPhone/iPad: SMB media import through Apple's Files provider

This is a **read-only, user-selected file import**, not a built-in SMB client or SMB directory browser.

## How to use

1. On the iPhone/iPad, open Apple's **Files** app, choose **Browse > ... > Connect to Server**, and enter the address of a NAS share (for example, `smb://192.168.1.10`). Authenticate in the system Files UI. TV-Next never receives or stores the SMB password.
2. In TV-Next open **本机文件与字幕** and choose **从文件 App / SMB 共享选择媒体**. Navigate the system document picker to the previously connected share and select a permitted MP4/M4V/MOV/MP3/M4A/AAC file.
3. The iOS Files provider grants temporary read access. TV-Next coordinates that read, copies the selected media in 1 MiB chunks to its app-owned temporary cache, then opens the local copy in AVPlayer. Progress may depend on SMB/Files downloading the document.

## Boundaries

- 2 GiB maximum, enforced both against reported size (when available) and against actual bytes copied. Empty files, directories, unsupported extensions and cancellation are rejected; failed/partial staging files are removed.
- No network credentials, provider URLs, SMB mount paths or media bytes are uploaded to the TV-Next server or persisted in the synced library. The temporary local copy consumes device storage and is deleted on normal local-media cleanup; an OS cache eviction may also remove it.
- The system Files app manages SMB authentication, transport and provider availability. No SMB write, remote browsing inside TV-Next, seek-over-SMB streaming, background sync or direct `smb://` AVPlayer URL is implemented.
- File-provider hydration and network errors can still occur. File-provider coordination may block while the system resolves a remote document; cancellation is checked during streaming but cannot guarantee immediate interruption of system coordination.
- Linux Swift smoke covers chunked copy, rejection and cancellation; macOS CI adds the same smoke, XCTest and production iPhone/iPad XCUI. A synthetic local file is not a real SMB share. Physical iPhone/iPad and actual NAS SMB verification remain open under P4 #5.

Implementation issue: #124. Parent: #5. Do not close either without its respective acceptance evidence.

## Simulator picker regression (2026-11-01)

The initial PR CI completed Web/API and native XCTest successfully but failed the new iPhone and iPad XCUI picker assertion: neither `Cancel` nor `取消` was visible through the app-scoped query. The media `.fileImporter` is now attached to the local-media section instead of the root view shared by other file importers. The UI test checks both the app and the Files document-provider accessibility hosts and emits their accessibility hierarchies on failure. This is a presentation/test-discovery correction, **not** proof of SMB NAS access. Final-HEAD iPhone/iPad XCUI and aggregate CI remain mandatory before merge.

### Follow-up after full CI 41231112970

The relocation-only fix still failed on both simulators: the app hierarchy showed the import button, but no system picker; the Files process hierarchy was empty. This revision replaces the media-only SwiftUI `fileImporter` modifier with an explicit `UIDocumentPickerViewController` hosted in a SwiftUI sheet. The same system Files provider owns SMB authentication and file selection; the existing bounded `LocalMediaStager` handles the selected security-scoped URL. The app-owned sheet has an explicit Close button for deterministic cancellation, including when the simulator's Files accessibility tree is absent.

XCUI now asserts the actual app-owned picker sheet opens, can be dismissed, and does not start playback on cancellation. It **does not** assert that the system Files process exposed a navigable SMB share or that the user can select a real NAS document; those remain physical-device acceptance gates. The final-HEAD complete iPhone/iPad XCTest/XCUI and Web/API/aggregate gates must succeed before merge.

### Follow-up after full CI 41240536489 (2026-11-01)

[Run 41240536489](https://github.com/Kahen/TV-Next/actions/runs/41240536489) again passed all six non-iOS business jobs, but both simulator XCUI jobs failed at the same SMB picker dismissal case. iPhone: the top-right close button was present in the accessibility tree at y=16 but UIKit's picker obscured its hit target (AX scroll-to-visible failed at `LibraryUITests.swift:160`). iPad: the tap returned without an error, but the button remained present after the 5-second dismissal wait (`LibraryUITests.swift:164`). Native unit tests and other UI cases passed; this is not an SMB transport failure.

The app-owned close control is now placed in a **bottom safe-area inset** with a minimum 44-point target, outside the top status-bar/embedded picker overlap. The XCUI test additionally waits for `isHittable` before tapping and still requires the sheet to disappear, the import entry to return, and the current media to remain empty. This is a targeted UI correction, not a relaxation of cancellation assertions. The change is **unverified until its final-head iPhone/iPad simulator and aggregate CI complete**; the system Files picker and real NAS SMB file selection remain separate physical-device gates.

## Cancelable import and copy progress (#126)

The Files/SMB media staging view now reports **bytes actually copied** from the coordinated provider URL and, when the provider reports a usable length, a bounded percentage. The system may still spend time hydrating the file before the first byte is available; this is an indeterminate phase rather than an invented network transfer percentage.

An explicit **取消媒体导入** action cancels the active Swift Task and its detached chunk-copy worker, clears the visible progress and invalidates stale callbacks. Entering the background or clearing the library also cancels. The worker checks cancellation before every 1 MiB read, deletes partial files and refuses to start AVPlayer on stale or cancelled completion. File-provider coordination may block and cannot be guaranteed to stop immediately.

Synthetic Swift smoke and XCTest assert exact chunk progress (1 MiB, 2 MiB, final bytes), a pre-cancelled task, deterministic cancellation after the first chunk, cleanup of partial files and absence of media history. Production iPhone/iPad XCUI checks that cancelling the document picker never starts copy progress. Real Files/SMB transfer, in-progress cancel interaction and NAS interoperability require separate physical-device acceptance; no native SMB protocol or signed release is claimed. Final HEAD full CI is required before closing #126.


## Cold-launch orphan cache reclamation (#128)

Files/SMB imports are intentionally session-only: the staged copy is not restored after a process restart. A force quit or crash during/after staging could leave an app-owned copy (up to 2 GiB) in `Caches/TVNextImported`. On a **new application process launch only**, TV-Next now removes abandoned **regular files with UUID basenames and one of the supported media extensions** from that private staging directory. It does not delete other names, unsupported extensions, subdirectories, symlinks or redirected cache roots. This is deliberately not a periodic cleanup while a player or import might be using a file.

Swift smoke/XCTest include positive, unrelated-file, unsupported-extension, directory, symlink, redirected-root and idempotency cases. The cleanup does not change Files provider authentication, media decoding, actual SMB hydration, or physical NAS compatibility. Final-head simulator and full integration CI are required before closing #128.

## Local storage headroom before import (#130)

Before allocating a staged copy, TV-Next checks the app cache volume's reported free bytes. When the Files provider reports a file size, that size must fit while leaving **64 MiB** free; when size is unknown, at least the reserve must remain. This preflight is conservative, may be unavailable on some volumes, and cannot guarantee that other apps will not consume space during the copy. Actual writes still enforce the existing 2 GiB limit, and Cocoa/POSIX disk-full write errors are presented as an actionable local-storage message. Failure and cancellation continue to delete partial copies. No SMB password, provider path or media content is sent to the server.

Swift smoke and XCTest cover exact reserve boundaries, unknown lengths, large integer arithmetic, both disk-full error families and preservation of unrelated errors. Existing iPhone/iPad XCUI and full integration remain required at the PR's final HEAD. Real iOS low-storage/SMB-provider behavior and physical NAS interoperability remain unverified.
