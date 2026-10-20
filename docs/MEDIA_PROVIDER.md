# MediaProvider V1: static FongMi Result adapter

The adapter defines an independent contract for later isolated Spider backends. It only operates on the user's manually supplied FongMi-style `Result` JSON and **never contacts media sources or executes plugins**.

## Supported data

Input JSON contains `class` and/or `list`. `list` items use `vod_id`, `vod_name`, `type_id`, `type_name`, `vod_year`, `vod_pic`, `vod_content`, `vod_director`, `vod_actor`, `vod_remarks`, `vod_play_from` and `vod_play_url`. Lines separate with `$$$`, episodes with `#`, episode name and URL with `$`. This is a bounded subset, not a general Spider parser; embedded delimiters, source-specific flags, headers, redirects and custom parsing are unsupported.

## Routes — all HTTP POST

| Endpoint | Additional request properties | Purpose |
| --- | --- | --- |
| `/api/v1/media/home` | `page`, `pageSize` | Categories and paginated list |
| `/api/v1/media/category` | `categoryId`, pagination | Filter imported entries by category |
| `/api/v1/media/search` | `query`, pagination | Case-insensitive local search of imported names |
| `/api/v1/media/detail` | `vodId` | Metadata, playback lines and episode names |
| `/api/v1/media/play` | `vodId`, `lineIndex`, `episodeIndex` | Plain HTTP(S) URI already in the imported JSON |

Each request includes `content` containing complete Result JSON. No state or credentials are stored server-side. For example, POST `/api/v1/media/home` with JSON:

```json
{"content":"{\"class\":[{\"type_id\":\"movie\",\"type_name\":\"Movies\"}],\"list\":[]}"}
```

Limits: at most 1 MiB content, 200 categories, 2000 entries, 30 lines and 400 episodes per line; pages 1–1000 with 1–100 items. Malformed requests return 400, missing videos 404, unsupported player directives 422. No remote URL is fetched. Only HTTP(S) without embedded userinfo and control characters is accepted for playback. Browsers may still block streams due to CORS or codecs.

The Web **影视目录** tab can browse, search, read details and select episodes from this static data. Any `example.org` test URL is a non-working placeholder, not an included content source.

## Outstanding for P2/P3

Permitted real provider/Spider fixtures, FongMi output variants, genuine cross-site search, iOS catalog parity, external config URLs, IPTV EPG, playback headers, robust parser delimiters and metadata-to-runtime adapters. Do not call this implementation a full FongMi frontend or Java/JS/Python compatibility.

Safety: keep untrusted Java/JAR/JS/Python execution outside the core API, isolate filesystem/network/CPU/memory, and enforce explicit allowlists. Merely returning provider metadata does not grant permission to fetch arbitrary URLs.
