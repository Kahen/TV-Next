# Live timeshift and programme catchup

Reference: **FongMi/TV `123cc086159b0f13bf54bdf64bacbc259ca47c88`**, inspected on 2026-10-28:

- [bean/Timeshift.java](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/bean/Timeshift.java): `{url,start,window}`, case-insensitive `{time}`/`%7Btime%7D`, Unix **milliseconds**, lower bound `max(start, now-window)`.
- [player/TimeshiftPlayback.java](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/player/TimeshiftPlayback.java): seek fetches a **Result JSON**, validates direct playback, replaces the playing source only after resolution; zero is the return-to-live sentinel.
- [bean/Catchup.java](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/bean/Catchup.java): distinct programme start/end templates, default/append, optional URL replacement, epoch seconds and explicit UTC date formats.
- [bean/Channel.java](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/bean/Channel.java) and [api/parser/LiveParser.java](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/api/parser/LiveParser.java): live-to-channel and global-to-M3U-entry catchup inheritance; channel-local declaration takes priority.

## Usage

Reload the subscription or import M3U after updating. Replay metadata is deliberately memory-only. Log into the family server on the client.

On Web/iOS, a playing source with valid `timeshift` displays a local date/time picker, the provider's current range, **播放所选时间**, **回到直播**, cancellation and failure feedback. Each selection is revalidated using the server clock. An expired, future, negative or invalid selection never silently clamps into a different programme. New requests invalidate old ones; a late returned capability is closed. Provider resolution failures leave the current playback unchanged. A later media decode/transport failure is still a player error.

XMLTV guide requests accept `pastHours: 0..168` (default zero for existing callers). Both clients request seven days and render up to the latest **40 completed programmes per channel** already present in the imported/cached XML. A **回看** button appears only for channels declaring catchup; it sends programme start/end separately from generic timeshift. No archive is fabricated or downloaded by selecting the guide. Feed refresh preserves the original bounded XMLTV transport and cache limits.

## API and supported subset

`POST /api/v1/subscriptions/replay`, device Bearer authorization required **before any provider I/O**:

```json
{
  "channel": {
    "name": "Owned live fixture", "group": "Live", "url": "https://example.org/live.m3u8",
    "timeshift": {"url": "https://example.org/seek?time={time}", "start": 1792915200000, "window": 3600000}
  },
  "time": 0,
  "timezone": "Asia/Shanghai"
}
```

Timeshift requires a past positive provider start, positive window, valid HTTP(S) template and `time == 0` or `max(start,now-window) <= time <= now`. RPC responses support a textual direct `url`, an optional object/JSON-string `header`, and no `parse`/`jx`/`playUrl`/DRM/provider-error requirements. RPC calls do not inherit private media headers. Result response headers apply only through the existing relay's original-origin policy. Array/multi-URL Result selection and parser chains are explicitly outside this subset.

To select **programme catchup**, send nonzero `time` and `stop`, and a channel `catchup: {type,days,source,regex,replace}`. Bounds: `1 <= days <= 30` (default seven), `now-days*86400000 <= time < stop <= now`. Modes: `default` (source is the complete URL), `append` (append to live URL, preserve existing query). Tokens:

| Token | Meaning |
| --- | --- |
| `{utc:...}` / `{utcend:...}` | Programme start/end in Unix seconds, matching original prefix semantics |
| `${(b)timestamp}` / `${(e)timestamp}` | Start/end in Unix seconds |
| `${(b)yyyyMMddHHmmss}` / `${(e)yyyyMMddHHmmss}` | Local format in the explicitly supplied IANA timezone |
| Same date token ending `\|UTC` | Format in UTC, independent of client/server timezone |

Both `${...}` and `{...}` forms work. Date format allowlist: `yyyyMMddHHmmss`, `yyyyMMdd`, `yyyy-MM-dd`, `HHmmss`, `HH:mm:ss`. DST is determined from the programme instant and named zone. `regex` supports a literal substring only; `replace` supports bounded literal `from,to`. Arbitrary provider regular expressions, unknown tokens/modes, unresolved templates and cross-origin programme templates return explicit errors. The Android `/PLTV/` implicit auto-detection is not enabled; an explicit provider declaration is required. Catchup configuration can express its `/PLTV/,/TVOD/` literal replacement.

Successful response: `{path,expiresAt,hls,time}` with `Cache-Control: no-store, private`. The path is an already registered relay capability. It does not disclose provider playback URLs, private headers or the device token. Existing DNS-pinned transport, redirect revalidation, public/explicit-LAN policy, request/output/deadline bounds and relay revocation/quotas remain in force. Media DNS validation occurs when the relay opens the upstream socket. See [MEDIA_RELAY.md](MEDIA_RELAY.md).

Original live URLs retain library identity. Replay templates, replay capability URLs and replay playback positions are excluded from saved/synced libraries; reloading the subscription restores metadata after restart. Capabilities are closed when superseded or the player is disposed. A response lost because the client connection was cancelled expires under the existing bounded session quota/idle timeout.

## Verification

Shared synthetic contract: `fixtures/fongmi-live-replay-golden.json`. Kotlin checks actual Result resolution, secret isolation, window boundaries, unsupported modes, UTC/Hong Kong/DST, M3U/nested JSON metadata and bounded historical XMLTV. MockMvc checks authorize-before-I/O, capability registration, response redaction and device revocation. Vitest checks no-session, zero sentinel, errors, late-response cleanup, EPG bounds and persistence. Swift smoke checks range/inheritance/ephemeral capability encoding; XCTest checks snapshot sanitization and player preservation on rejected replay. The existing final-head integration gate builds both native simulator families and executes real browsers/Compose/NAS/isolation.

Only synthetic fixtures are used. This increment does not establish real-provider compatibility, physical device quality, a signed build or completion of P2/P3/P4.

## Replay retry and concurrent selections

- Native iOS replay retry requests a **new** server capability for the same ephemeral selected time, stop and timezone. The previous capability is closed; a replay without original selection metadata requires the user to choose a time again. The selection and capability are excluded from local snapshots.
- Web XMLTV programme buttons share a guide-scoped request owner. When a newer programme is selected, a slower previous response is discarded and its returned relay ticket is closed. Switching guides/channels or leaving the view invalidates pending selections. This does not assert real-provider or physical-device playback.
