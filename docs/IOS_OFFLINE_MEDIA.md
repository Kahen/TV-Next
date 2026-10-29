# Native offline media

Open **功能导航 → 离线媒体**, enter a media file URL and a display name, then choose
**下载到本机**. For eligible current media, **填入当前媒体** copies its address into
the form. Keep the application in the foreground on Wi-Fi until completion.
The completed list survives restart; **离线播放** opens the local file in the
existing AVPlayer, caption and system media-control path. Deleting an active copy
releases the AVPlayerItem before deleting the file. The normal library Clear
action and home-server sync do not delete or upload offline copies; each copy has
an explicit Delete control in the offline list.

Supported: direct HTTP(S) MP4/M4V/MOV/MP3/M4A/AAC files without additional request
headers. Byte/header validation rejects empty files, HTML/error pages and HLS
manifests masquerading as media. Actual codec support remains device-dependent.
HLS asset packages, live recordings, DRM, authenticated media-relay downloads,
background transfers, byte-range resumption and automatic retries remain pending.
Cancelled/interrupted transfers must be started again. This feature does not
download or execute plugins, or bypass provider access restrictions.

The ephemeral URLSession has no cookie/credential storage, refuses redirects,
uses standard TLS verification and does not allow cellular transfers. Downloads
stream to temporary disk files with a 512 MiB per-file cap, a 2 GiB total cap and
20 completed-file limit. A transfer is cancelled when the app backgrounds.
Complete files move into Application Support only after final status, MIME,
byte-size and format-signature validation. An atomic versioned JSON manifest
contains only generated UUID filenames, display names, extensions and sizes;
source URLs, signed queries, credentials and binary resume data are not stored.
The offline directory is excluded from backup. Startup checks recorded files
and removes partial/orphan copies within that directory. Storage errors leave
the last committed catalog available. Download errors use fixed messages so a
URLSession error cannot display a private query string.

Automated acceptance covers catalog restore/deletion, corruption, quotas,
unsupported URLs, format headers, owned localhost MP4 download and cancellation,
plus production SwiftUI download/relaunch/local-play/delete on iPhone and iPad
simulators. Final-head CI must pass before merging. Physical codec, disk-pressure
and energy tests remain in #38/#5.

The same native increment connects subscription `subtitles` resources to the
existing SRT/VTT/text ASS parser and AVPlayer overlay. Loads use the bounded
server text-resource transport; only the latest selection for the same playback
generation can install cues. Switching media/server, importing/removing local
captions and backgrounding cancel pending loads. Parse/network failure preserves
the previous captions. These resources are fetched explicitly, not downloaded
into the offline catalog. Additional provider-specific subtitle headers and
styled ASS rendering remain outside this subset.
