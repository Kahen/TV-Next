# XMLTV / live EPG

## Supported flow

1. Import a lawful M3U playlist under **播放列表** in Web or native iOS. Channel `tvg-id` fields are preserved.
2. Open **直播节目表**, paste an authorized UTF-8 XMLTV document or choose a local `.xml` / `.xmltv` file (up to 2 MiB).
3. Click **解析节目表**. The browser sends the XML text and the **first 300 imported channels** to the self-hosted API endpoint `POST /api/v1/epg/guide`.
4. The API matches an XMLTV `<channel id="...">` to M3U `tvg-id` by exact ID. When no ID matches, it uses a **unique** case-insensitive whitespace-normalized XMLTV `display-name`. If multiple XMLTV channels have the same normalized alias, no name fallback occurs.
5. The results show the programme active at server time and upcoming programmes starting within the selected 6/12/24/48-hour window. Dates are returned as UTC ISO-8601 instants and formatted by the browser's local timezone. Clicking a listed imported channel requests normal playback through the existing player.

## API

`POST /api/v1/epg/guide`, JSON:

```json
{
  "xml": "<tv><channel id=\"demo\"><display-name>Demo TV</display-name></channel><programme channel=\"demo\" start=\"20261020190000 +0800\" stop=\"20261020200000 +0800\"><title>News</title></programme></tv>",
  "channels": [{"id": "demo", "name": "Demo TV"}],
  "at": "2026-10-20T11:30:00Z",
  "hours": 12
}
```

`at` is optional and must include a timezone (defaults to current server UTC instant); `hours` defaults to 12 and must be 1–72. A programme with `start <= now < stop` is current; upcoming entries start within `[now, now + hours)`. Up to 20 upcoming programmes per channel are returned.

XMLTV accepts twelve- or fourteen-digit timestamp forms, e.g. `202610201900` or `20261020190000`, optionally followed by `+0800`, `+08:00`, `-0500` or `Z`. Missing offsets are interpreted as UTC; this can be wrong for local-time XMLTV sources, so prefer explicit offsets. Missing or invalid programme timestamps and empty titles are skipped, not guessed.

## Security and limits

The unauthenticated `/epg/guide` endpoint only parses the supplied text. Authenticated saved feeds fetch explicitly configured XMLTV URLs using the existing DNS-pinned transport. Neither flow downloads logos, follows XML external references, resolves IPTV media or executes Spider. Java SAX XML parsing enables secure-processing, explicitly disallows DOCTYPE and disables external entities/DTDs. Malicious DOCTYPE/XXE fixtures must fail with 400.

Per request: XML text up to 2,097,152 UTF-8 bytes, 1–300 M3U channels, 1–72-hour horizon. Parser captures at most 1,000 XMLTV channel aliases and 20,000 programmes; nesting is capped at depth 20, caption/text fields are bounded. Results preserve the request's channel order. Entries lacking unique matches remain visible as unmatched instead of silently stealing another programme.

Do not expose the unauthenticated development API to the public internet. Local import XML is processed in memory. Saved feed URLs and last valid XML are stored in the account database and its backups; URLs may contain sensitive access parameters. A production reverse proxy should also enforce HTTP request size/time/rate limits.

## Saved subscriptions and automatic refresh

Log in under **家庭服务器**, then use **节目表订阅** in Web or iOS. Save a name, HTTP(S) XMLTV / XMLTV.gz URL and refresh interval of 15–1440 minutes (default 360). New enabled feeds are fetched on the next scheduler pass; **立即刷新** attempts a download immediately. Select **显示节目表** to match the cached XML against the current playlist. No stream starts until **播放频道** is clicked.

Endpoints require the current device bearer token. IDs are scoped to its user; callers cannot select another account:

| Method | Path under `/api/v1/home/epg/feeds` | Body / behavior |
| --- | --- | --- |
| GET | `/` | List account feed status; omits cached XML |
| POST | `/` | `{name,url,intervalMinutes,enabled}` creates a feed |
| POST | `/{id}/refresh` | One attempt; returns updated status including `lastError` |
| POST | `/{id}/guide` | `{channels,at?,hours?}` returns the standard EPG model |
| POST | `/{id}/remove` | Deletes settings and cached XML |

Each account can save 10 feeds; the server has a fixed 200-feed budget. Both wire and decompressed feed bodies are capped at 1 MiB by the shared transport; offline text imports remain 2 MiB. HTTP gzip and gzip file magic are supported, including servers that omit Content-Encoding for `.gz` files. Input must decode as valid UTF-8. Invalid XML, XXE, network errors and oversized compressed output retain the previous valid cache and record a generic failure. Check `updatedAt`/`lastError` before relying on cached programme times.

The one-minute scheduler selects enabled due feeds for accounts with at least one non-revoked unexpired device. A database lease prevents simultaneous refresh of the same feed across API instances and enforces one minute between manual attempts, including failed attempts. Failures back off by the configured interval. Restarts retain settings, last-attempt time, next deadline and last good guide in H2/PostgreSQL. A process interrupted during refresh leaves a one-minute lease before retry. LAN origins require explicit administrator approval with `TV_NEXT_LAN_ORIGINS`; loopback, metadata and link-local endpoints remain denied. Arbitrary request headers are not accepted for EPG subscriptions. Delete a feed to stop scheduling it.

The Web view rejects stale responses on channel changes/logout and binds play buttons to the playlist snapshot used for matching. iOS provides bounded Files import, paste, saved feeds and equivalent guide/playback controls; it shares the JSON contract fixture with Kotlin. Dates display in the device timezone.

## Remaining compatibility

The explicit timeshift Result and bounded programme catchup subset now has Web/iOS controls and historical guide entries; see [LIVE_REPLAY.md](LIVE_REPLAY.md). Long-tail replay protocols, FongMi EPG placeholder URL substitution, credential-header feeds, country-specific synonyms, large regional guide support and real licensed IPTV/Apple-device playback verification remain open. Code integration is separate from final device acceptance.
