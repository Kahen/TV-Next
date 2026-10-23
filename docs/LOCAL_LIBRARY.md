# Local media library (P1)

Status: initial implementation. This is **local persistence**, NOT account-based synchronization.

## Features

- Web stores normalized M3U channels, favorites, recent streams and finite-duration VOD progress in the current origin's localStorage (schema key: tv-next-library-v1, version 1).
- iPhone/iPad independently store a bounded Codable snapshot in app UserDefaults and use AVPlayer for finite-VOD resume. Offline M3U file/text parsing does not require a server.
- Choosing a channel adds it to recent; repeated plays move it to the top.
- Favorites are keyed by the media URL; replacing a playlist preserves favorites and history where the stored URL is still available.
- Resume time is saved periodically and on pause, for finite-duration items longer than 60 seconds. Live/infinite streams and nearly finished items do not retain progress.
- Web exposes a confirmation before clearing data; iOS uses a destructive confirmation dialog.

## Local quotas and recovery

- Input M3U text is capped at 1 MiB; iOS parser accepts up to 20,000 lines and stores a maximum of 1,500 channels. Web API may parse up to 5,000, but Web persists the first 1,500.
- Favorites are capped at 300 and recent items at 100. Web saves up to 250 playback positions.
- Web snapshots are limited to **2,000,000 UTF-8 bytes**, not JavaScript UTF-16 code units. Oversized persisted data is rejected on load; an oversized save leaves the previous valid snapshot untouched. Browser quotas can be stricter; this is a storage-integrity limit, not a media-file size limit.
- Web rejects invalid protocols and embedded basic-auth URLs when loading stored items, ignores corrupted/wrong-version records, and handles localStorage quota failures without crashing.
- Browsers may discard data in private browsing or storage-pressure situations. Deleting app/site data loses the library. iOS app uninstall may also delete its UserDefaults data.

## Security and privacy

- Metadata and media URLs, including any **query-string tokens**, are stored locally on the device/browser. Avoid sensitive links on shared devices; do not assume this local store is encrypted.
- The backend is currently stateless and does not store account or media-library information.
- JSON configuration inspection does not execute Spider scripts; no arbitrary remote code runs in the Web/iOS clients.
- No cross-device synchronization, backup/export, CDN token redaction, encryption-at-rest guarantees or multi-user isolation is supplied in P1.
- Do not expose the development API to untrusted networks. Supply only media sources that you are authorized to access.

## Known gaps / next steps

- Platform parity tests for stored progress and actual stream playback, including iOS background/foreground lifecycle behavior.
- Persistent playlist names, group filters, import/export and migration strategy beyond schema version 1.
- Playback speed in iOS, audio/subtitle track selection, PiP, AirPlay and file playback.
- P5: opt-in authenticated synchronization and media library backups.

## Shared M3U metadata parity fixture (P1 partial)

The synthetic, source-free `fixtures/p1-m3u-golden.m3u` and expected `fixtures/p1-m3u-golden.json` are consumed by Kotlin API tests and iOS Swift parser smoke tests. The tested subset covers commas inside quoted EXTINF attributes and titles, missing title fallback to tvg-name, EXTGRP override, unsafe scheme/credential rejection and invalid logo filtering. Both clients must agree on channel name, URL, group, logo and tvgId.

The Web client imports M3U through the API, while iOS defaults to its offline parser. The API can return up to 5,000 channels, whereas iOS stores up to 1,500; this fixture verifies **metadata semantics only**, not large-playlist parity, actual streaming, CORS, browser E2E, or physical Apple devices. See `docs/ACCEPTANCE.md` before declaring P1 complete.
