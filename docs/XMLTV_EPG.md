# XMLTV / live EPG — initial P2 implementation

## Supported flow

1. Import a lawful M3U playlist under **播放列表** in Web. Channel \`tvg-id\` fields are preserved.
2. Open **直播节目表**, paste an authorized UTF-8 XMLTV document or choose a local \`.xml\` / \`.xmltv\` file (up to 2 MiB).
3. Click **解析节目表**. The browser sends the XML text and the **first 300 imported channels** to the self-hosted API endpoint \`POST /api/v1/epg/guide\`.
4. The API matches an XMLTV \`<channel id="...">\` to M3U \`tvg-id\` by exact ID. When no ID matches, it uses a **unique** case-insensitive whitespace-normalized XMLTV \`display-name\`. If multiple XMLTV channels have the same normalized alias, no name fallback occurs.
5. The results show the programme active at server time and upcoming programmes starting within the selected 6/12/24/48-hour window. Dates are returned as UTC ISO-8601 instants and formatted by the browser's local timezone. Clicking a listed imported channel requests normal playback through the existing player.

## API

\`POST /api/v1/epg/guide\`, JSON:

\`\`\`json
{
  "xml": "<tv><channel id=\"demo\"><display-name>Demo TV</display-name></channel><programme channel=\"demo\" start=\"20261020190000 +0800\" stop=\"20261020200000 +0800\"><title>News</title></programme></tv>",
  "channels": [{"id": "demo", "name": "Demo TV"}],
  "at": "2026-10-20T11:30:00Z",
  "hours": 12
}
\`\`\`

\`at\` is optional and must include a timezone (defaults to current server UTC instant); \`hours\` defaults to 12 and must be 1–72. A programme with \`start <= now < stop\` is current; upcoming entries start within \`[now, now + hours)\`. Up to 20 upcoming programmes per channel are returned.

XMLTV accepts twelve- or fourteen-digit timestamp forms, e.g. \`202610201900\` or \`20261020190000\`, optionally followed by \`+0800\`, \`+08:00\`, \`-0500\` or \`Z\`. Missing offsets are interpreted as UTC; this can be wrong for local-time XMLTV sources, so prefer explicit offsets. Missing or invalid programme timestamps and empty titles are skipped, not guessed.

## Security and limits

The API is deliberately **offline-only**: it does not fetch XMLTV feeds from the Internet, download channel logos, process external references, resolve IPTV URLs or execute Spider. Java SAX XML parsing enables secure-processing, explicitly disallows DOCTYPE and disables external entities/DTDs. Malicious DOCTYPE/XXE fixtures must fail with 400.

Per request: XML text up to 2,097,152 characters, 1–300 M3U channels, 1–72-hour horizon. Parser captures at most 1,000 XMLTV channel aliases and 20,000 programmes; nesting is capped at depth 20, caption/text fields are bounded. Results preserve the request's channel order. Entries lacking unique matches remain visible as unmatched instead of silently stealing another programme.

Do not expose the unauthenticated development API to the public internet. Inputs are processed in memory and are not stored in a database, but transmitted XML may contain sensitive source metadata. A production reverse proxy should also enforce HTTP request size/time/rate limits.

## Explicitly unfinished

This is **not** automatic EPG scheduling. There is no URL subscription/download, periodic refreshing, disk cache, time-shift playback, catch-up, XMLTV.gz decompression, provider-authenticated fetch, smart FongMi EPG substitutions, country-specific name synonyms, EPG on native iOS, or tested behavior on real licensed IPTV feeds. These remain P2/P5 deliverables.

Automated fixture coverage: timezone conversion, active/upcoming boundaries, ID precedence, unique-name matching, ambiguous aliases, malformed XML, DOCTYPE/XXE, invalid query limits and HTTP response contract. Browser/real-device integration tests remain to be done.
