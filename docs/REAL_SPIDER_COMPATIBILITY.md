# Real subscription compatibility — 2026-10-28

The user explicitly supplied `http://www.饭太硬.net/tv` for compatibility testing.
It is an operator-supplied test input, not a built-in media source. No subscription
payload, plugin binary, media stream or credentials are redistributed by this repo.

## Observed sample

- HTTP 200, `image/x-ms-bmp`, 20,063 bytes. JPEG-like binary prefix followed by
  the original eight-alphanumeric-character `**` Base64 envelope.
- Encoded document includes `//` JSON comments. After decoding: 49 sites, all
  `type: 3`, using `csp_*` entry points and the shared `spider` reference.
- Config response SHA-256: `ae2ea896d5efa5b379d8f41066be570067f9415a6f04659cdc524ceec53ae167`.
- Referenced ZIP/JAR: 1,448,574 bytes; advertised MD5 matched
  `b55978c4fe6d12e2fea9075f17c8a67a`; observed SHA-256
  `88e67402129e7db92669fb351397ecd4d09709e6c70b577f22a19cfb0ad5f204`.
- Contents: `classes.dex`, two native `.so` assets (v7/v8 guards), manifest and
  protected guard data; **zero JVM `.class` files**. This cannot execute in the
  current Java 21 worker. Static inspection is not code execution or playback.

These are dated observations, not an assertion that an externally maintained
URL will continue returning the same bytes or that every site works.

## Original implementation mapping

Reference: [FongMi/TV `123cc086`](https://github.com/FongMi/TV/tree/123cc086159b0f13bf54bdf64bacbc259ca47c88).

| Upstream | TV-Next compatibility |
| --- | --- |
| `catvod/.../utils/Decoder.java`: load, Base64 envelope, relative URLs | Subscription transport can extract an ASCII Base64 envelope from a binary prefix; decoded JSON remains strict UTF-8 and size-bounded |
| `catvod/.../utils/Json.java`: Gson parsing accepts comments | Subscription-specific Jackson reader allows Java-style comments; other API parsers remain strict and trailing JSON documents fail |
| `app/.../api/config/VodConfig.java`: sites and inherited spider JAR | Existing normalized site metadata, inherited JAR, relative resources and explicit depot selection |
| `app/.../api/loader/JarLoader.java`: `DexClassLoader`, `csp_` class names and Android Context | Requires an Android runtime for this sample; a pure JVM loader cannot substitute for Android DEX and native libraries |
| `app/.../server/process/SpiderTest.java`, `SpiderTestSession.java` | Optional [Android bridge](ANDROID_SPIDER_BRIDGE.md) implements the original session/load/run/poll/delete contract for approved stateless type-3 sites; real ARM-host validation remains pending |

Unicode DNS names are normalized to IDNA ASCII before DNS resolution. Raw URL
paths/queries are preserved; userinfo, fragments, malformed ports, escaped
authorities and controls remain rejected. Existing DNS pinning, redirects,
private-address policy, response/gzip limits and transport quotas still apply.

## Reproduce subscription loading

With the API running, explicitly supply an authorized URL:

```bash
python3 scripts/real_subscription_probe.py --subscription-url '<authorized-url>'
python3 services/spider-runtime/jar_inspect.py /path/to/explicitly-obtained.jar
```

The first command prints counts/fingerprints only. It does not download or run
plugins. The second scans a local ZIP without executing it, including detection
of DEX mixed into an otherwise JVM-compatible archive. `unsupported` is expected
for this Android/native sample and exits 2.

Built API evidence: [run 40675302304](https://github.com/Kahen/TV-Next/actions/runs/40675302304)
loaded 49 type-3 sites successfully; normalized-config SHA-256
`2984deb655ea494621985bf0b48deae34839526672c79991e01d3dbd643d0acf`.

Actual ARM Android plugin execution, home/search/detail/player behavior and real
Apple playback remain unverified until the Android host and device media matrix
are available. P2/P3/P4/P6 remain open.
