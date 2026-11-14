# Native WebDAV subtitle selection

An iPhone/iPad user can choose an SRT, VTT, ASS or SSA file from the connected
WebDAV directory and attach it to the selected playback. The player uses its
existing external-caption text overlay, offset and remove controls. The browser
shows the current subtitle, loading state, a cancel action and sanitized errors.
A failed or cancelled replacement retains the preceding subtitle. No media
selection means subtitle actions are disabled. The media-only filter intentionally
hides subtitle files; disable it to select one.

## Source and compatibility

Reference FongMi/TV commit `097917c1c5eb6c94a14b2ede3f371a681dbb751f`,
[`SubtitleArchive.java`](https://github.com/FongMi/TV/blob/097917c1c5eb6c94a14b2ede3f371a681dbb751f/app/src/main/java/com/fongmi/android/tv/utils/SubtitleArchive.java):
explicit external subtitle selection, case-insensitive supported extensions and
bounded downloads. This increment supports the four existing TV-Next text formats.
It does not implement FongMi's ZIP extraction, TTML, styled ASS, font loading,
karaoke, automatic filename matching or cloud login.

## Transport and lifetime

- The immutable connected WebDAV account authorizes GET only within its validated
  HTTP(S) origin and root. Basic credentials require HTTPS. Editing the connection
  form cannot change credentials on a pending or existing connection.
- Requests run on the Apple device, without the TV-Next server. Every redirect is
  rejected, including same-origin redirects. Cookies, credential storage and cache
  are disabled on the ephemeral session. Only a complete HTTP 200 response is
  accepted, with a 15-second request and 20-second resource timeout.
- DAV size metadata can reject a known oversized file early. Declared HTTP length
  and actual received chunks independently enforce the 1 MiB cap. Unknown/stale
  metadata does not bypass the actual-byte limit.
- UTF-8 and BOM UTF-16 are the defaults. GB18030 is an explicit per-selection
  choice in the WebDAV browser, captured before the request, and is not persisted.
- Subscription and WebDAV loads share one caption request lifetime. A new choice,
  local Files import, subtitle removal, connection replacement/disconnect or
  playback change cancels the previous load. The playback generation and exact
  AVPlayerItem must still match before applying cues. Same-URL replay is a new
  playback. Failed/cancelled requests cannot change the prior cues or offset.
- Credentials, subtitle bytes and selected file URLs are not persisted. Parsed
  cues already attached to unrelated playback remain after disconnect, while an
  in-flight import is cancelled. Disconnecting active WebDAV media retains the
  existing media credential-revocation behavior.

## Verification

Added request-policy XCTest, cross-source/latest-choice/cancellation/error
regressions, and real loopback GET smoke for formats, UTF-16/GB18030, redirect,
status, declared/chunked over-limit responses and cancellation. The production
SwiftUI test selects a subtitle, checks failed replacement retention and clears
the selection on same-URL replay. The original PROPFIND tests remain required
because both methods share the bounded transport.

Local Python fixture tests pass. Final-head iPhone/iPad simulator and complete
integration checks are required before merge. HTTPS authentication is covered by
request-policy assertions, not a live TLS NAS test. Real WebDAV server, physical
Apple device and release acceptance remain separate in #5 and #38.

## ASS detection regression (2026-11-14)

The shared iOS text-caption parser now selects ASS/SSA parsing only when the
first nonempty line is a recognized ASS section header (`[Script Info]`,
`[Events]`, `[V4 Styles]` or `[V4+ Styles]`). Previously, an SRT/WebVTT
dialogue containing a literal `[Events]` line was misclassified as ASS and
failed to load. This affects Files, SMB, subscription and WebDAV subtitle
selection equally; no new formats or remote fetching permissions are added.

Positive XCTest and standalone Swift smoke cover literal SRT/WebVTT dialogue,
and existing valid ASS headers. Negative XCTest checks malformed ASS timelines.
The final branch HEAD still requires both iPhone/iPad simulators and complete
integration CI before merging. No physical device or real NAS compatibility
is inferred from these fixtures.
