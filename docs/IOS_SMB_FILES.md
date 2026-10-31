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
