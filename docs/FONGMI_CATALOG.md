# FongMi configuration catalog preview (P2 first slice)

## What is implemented

Paste a FongMi-style JSON config in the **配置检查** tab. Web calls the original static inspector plus `POST /api/v1/catalog/preview`. The new endpoint parses supplied text only and returns:

- `sites`: `key`, `name`, `type`, `searchable`, `hide`, `categories`, and a fixed `mode=preview-only`.
- `liveSources`: `lives[].name`, `groups[].name`, `channel[].name`, `channel[].urls` count and an optional simple `directUrl`.
- Warnings and a count of immediately clickable plain HTTP(S) live addresses.

The field mapping was based on the upstream `FongMi/TV` Android `Site`, `Live`, `Group` and `Channel` classes. This is a **compatible metadata subset**, not full Spider or IPTV protocol parity.

## Security and behavior

- The API **does not download configs, URLs, images or plugins**. Raw `spider`, `api`, `ext`, `header`, cookies, authorization headers and script sources are **not returned** by the catalog preview.
- Only a stream entry that is already a plain HTTP(S) URL without embedded credentials or control characters becomes `directUrl`. Exotic syntax, `script://` routes, extension-based sources and source-specific headers require future adapters.
- The Web UI never automatically starts playback; a user must click an available channel. Browser playback still depends on CORS, codec and source permissions. User-provided media should be legally accessible.
- The response is bounded: at most 1000 sites, 50 live sources, 100 groups per live source, 1000 channels per group and 5000 total channel descriptors. Max submitted content length is 1 MiB.
- No network-origin Spider, arbitrary proxy, DNS override, bypass, account persistence or authentication is added by this phase.

## Not yet implemented

Search, home feeds, category filters, title detail, episodes, play line switching, XMLTV EPG, P2 navigation on iOS, nested configuration references, DRM/header-heavy IPTV, Spider adapters and full FongMi fields. These remain open in the roadmap and Issues #3 and #4. This catalog preview alone is not a substitute for FongMi TV.
