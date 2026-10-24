# TVBox / FongMi compatibility implementation

Reference source: [Kahen/TV release 0af3b31a1783b8fa4f0ce12e52ac9fad78ddfb1e](https://github.com/Kahen/TV/tree/0af3b31a1783b8fa4f0ce12e52ac9fad78ddfb1e). GPL-3.0 attribution is retained in NOTICE.md and LICENSE.md. These are implementation statuses, not physical-device acceptance.

| Original source | TV-Next implementation | Covered semantics |
| --- | --- | --- |
| api/Decoder.java | Subscriptions.kt | JSON, eight-character `**` Base64 wrapper, `2423` AES-CBC envelope, relative resource paths |
| api/config/VodConfig.java | Subscriptions.kt; SubscriptionBrowser/Section | `sites`, `urls` multi-depot selection, `spider`, unknown fields preserved |
| bean/Site.java; gson/ExtAdapter.java | Subscriptions.kt | default type 0; searchable/quickSearch/changeable defaults; hide; structured/string ext; per-site jar/global spider inheritance |
| api/SiteApi.java | SubscribedProvider.kt | type 0 XML `videolist`; type 1/2 JSON `detail`; type 4 `filter`, `extend`, category URL-safe base64 `ext`, `play`/`flag`; search `wd`/`quick`, page 1 omission; original query string retained |
| bean/Result.java; bean/Vod.java | XmlVodAdapter.kt; MediaProvider.kt | XML categories/video/dl/dd; JSON class/list/vod_*; lines and episodes; remote pagination is not applied twice |
| bean/Flag.java; gson/DanmakuAdapter.java | SubscribedProvider.kt | opaque type 4 playback IDs (including cloud share/file IDs); string/array/encoded-array danmaku sources; subtitles; playback headers |
| bean/DanmakuData.java | Web/Swift DanmakuParser | XML `p` fields in seconds, RGB color, modes 1/4/5/6, entity decoding; bounded dandanplay JSON extension |

Both clients have subscription URL/paste inputs and original site selection. Web also has bounded concurrent cross-site search with cancellation. iOS uses the same server contract. Cookie/Authorization and other private playback headers are excluded from local snapshots. Web may retain User-Agent, Referer and Origin; a restored channel that required private headers asks for subscription reload.

## Network behavior

The server pins a validated DNS answer to each socket, verifies TLS hostname/SNI, revalidates and pins up to three redirects (stripping custom headers across origins and denying cross-origin POST replay/HTTPS downgrade), limits concurrent calls to 8, connect/read timeouts to 3 seconds and response wall time to 8 seconds (DNS lookup is OS-managed). Bodies are limited to 1 MiB compressed and decoded UTF-8; gzip is bounded. Hop-by-hop headers, Host overrides and CR/LF injection are rejected. Streaming media bytes do not go through this text transport.

Private-address destinations are denied by default. For your own LAN OpenList/provider service, explicitly set `TV_NEXT_LAN_ORIGINS` to exact origins such as `http://192.168.2.10:5244`. Each socket remains DNS-pinned. Only site-local LAN addresses are permitted by this opt-in; loopback, link-local/metadata and multicast stay denied. Do not expose these development services publicly without authentication/TLS deployment controls.

## Cloud drives

Web and native iOS AList/OpenList browsing uses the project's native `POST api/fs/list` and `POST api/fs/get` operations with user-provided session/API token, folder password and page. Tokens are kept only in UI/request memory and can be cleared with Disconnect. The returned signed/raw URL is used for playback. `fs/get.header` is presentation HTML and is deliberately never interpreted as a media HTTP header. AList/OpenList upstream API reference: [OpenListTeam/OpenList server/handles/fsread.go](https://github.com/OpenListTeam/OpenList/blob/main/server/handles/fsread.go).

Aliyun/Alipan, Quark, UC, 115 and other original TVBox cloud providers commonly live in external type 3 Spider code, rather than this TV Android host. Their metadata and opaque IDs must be retained. This change supports their HTTP type 4 counterparts; it does **not** claim direct cloud login, QR/OAuth, share-password flows or Android type 3 execution. No fabricated successful provider compatibility results are recorded.

## Explicit pending compatibility

- Android type 3 JAR/QuickJS/Python activation and actual provider corpus; current isolation harness is bundled-fixture only.
- WebView/sniffing parser chains (`parse`/`jx`/`playUrl`) and non-HTTP protocols; these fail explicitly rather than playing a webpage as video.
- Authenticated Web/iOS media relay supports header-dependent HTTP byte ranges and HLS child playlists/segments/AES-128 identity keys. See [MEDIA_RELAY.md](MEDIA_RELAY.md) for limits, including redirects, opaque resource IDs and credential scope. Cross-origin headers are intentionally stripped. DASH, DRM, continuous raw live transport and oversized non-range responses remain unsupported.
- Full live catchup, client category-filter controls, and interactive login/QR action workflows. Live TXT/M3U/nested JSON and external references, per-channel headers and type 4 folder navigation are implemented; HTTP actions return data without executing arbitrary UI instructions.
- ASS styling, automatic danmaku search endpoints and native PiP subtitle/danmaku composition.

Synthetic protocol tests are derived from these source paths. Real cloud accounts, original external Spider artifacts and physical iPhone/iPad playback still require separate evidence. P1–P6 are not all complete.

Original player mapping: `player/exo/ExoMediaSourceFactory.java` calls `setDefaultRequestProperties` on its HTTP data source. TV-Next retains those playback-result headers and applies them on the server for original-origin media requests; Apple/browser players receive registered capability URLs instead of being given private HTTP headers. This is an HTTP/HLS subset, not a port of Android ExoPlayer.
