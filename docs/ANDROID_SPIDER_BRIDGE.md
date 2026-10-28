# Experimental Android Spider bridge

This adapter delegates approved type-3 `csp_*` providers to an **existing,
separate Android host running FongMi** with the pinned `SpiderTest` HTTP API.
It does not add an Android emulator to NAS, convert DEX to JVM, implement an
Android runtime, or make ARM native plugins portable to an x86 JVM or iPhone.

Reference: original [SpiderTest.java](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/server/process/SpiderTest.java)
and [SpiderTestSession.java](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/api/loader/SpiderTestSession.java).
The ordinary Java/Node/Python Docker fixture harness is unchanged.

## Supported protocol

Each invocation creates a private session with `POST /spider-api`, loads the
approved api/ext/jar via `/load`, polls `GET /spider-api` with
`X-Spider-Session`, invokes `/run`, polls the bounded result, and attempts
`DELETE /spider-api` on success, failure, timeout and interruption. An upstream
session expires after 15 minutes if cleanup cannot reach the host. Sessions,
upstream snapshots, stack traces and tracing metadata are never returned to
clients or stored in the account sync cache. Only parsed media models use the
existing device-private catalog/search cache.

| TV-Next operation | Original method/arguments |
| --- | --- |
| home | `home([true])`, then `homeVod([])` if the first result has no videos |
| category | `category([tid,pageString,true,filters])` |
| search | `search([keyword,quick,pageString])`; upstream selects the correct overload |
| detail | `detail([[id]])` |
| player | `play([flag,opaqueEpisodeId,vipFlags])` |

Returned direct HTTP(S) playback goes through the existing media model and
capability relay paths. Unimplemented parser/WebView chains are still rejected.
This first bridge uses fresh instances per invocation. Interactive actions,
stateful cloud login/session reuse, plugin `proxy://` or Android-loopback media,
live callbacks, arbitrary uploads, file access, JS/Python/Node entry points and
runtime installation are **not supported**. A stateless contract test does not
establish actual site compatibility.

## Operator setup

Use a dedicated ARM Android test device for DEX/native providers that need ARM.
The original test HTTP API can execute code and has no account authentication;
keep it on an isolated trusted network reachable only from the API server. Do
not put secrets or other user accounts on that runtime. Its Android/network
isolation is a separate trust boundary and has not been independently audited.

After obtaining/reviewing the allowed plugin and its declared checksum, load an
authorized subscription and select one site to print its candidate init hash:

```bash
python3 scripts/real_subscription_probe.py \
  --subscription-url '<authorized-url>' --binding-site '<exact-site-key>'
```

The command does not execute or approve a plugin. The hash covers the exact key,
api, inherited/per-site jar reference, ext and global flags, including UTF-8 byte
lengths. Changed initialization inputs require a new administrator binding.
Legacy inline `;md5;<32 hex>` is required and checked by FongMi on download; MD5
is a legacy integrity check, not a security review or a signature.

Configure the server (both Compose variants forward these variables):

```text
TV_NEXT_SPIDER_ANDROID_URL=http://192.168.50.10:9978
TV_NEXT_LAN_ORIGINS=http://192.168.50.10:9978
TV_NEXT_SPIDER_BINDINGS=<approved-init-sha256>[,<another-approved-init-sha256>]
```

No host or bindings are enabled by default. The host address is an origin, never
a client-supplied URL. Existing DNS pinning and explicit private-origin checks
apply, and bridge redirects are rejected. TV-Next device authentication is
required before any type-3 browse/search/detail/player/action request; account
bearers never go to Android. Only a fresh host-generated UUID is sent there.

Limits: two concurrent invocations, no waiting queue, 1 MiB bounded HTTP responses,
8-second upstream operations and a 15-second total request budget (detail/player
share one budget). Web/native cross-source search uses at most two simultaneous
sites when Android sites are selected. Client cancellation discards stale UI
results; the server bounds in-flight Android work even when servlet disconnects
do not interrupt its thread.

## Evidence and remaining gates

Tests emulate the pinned original session state machine and verify all five
operation mappings, opaque IDs, inherited JAR/flags, auth/revocation, binding
changes, invalid session tokens, timeout/interruption, error redaction, cleanup,
and client capability selection. These are **synthetic HTTP contract tests**.

The real supplied subscription loads through the built API in
[run 40675302304](https://github.com/Kahen/TV-Next/actions/runs/40675302304):
49 sites, all type 3. Real plugin execution and playback have **not** run because
no ARM Android host is available in this environment. Test the pinned sample on
that host before reporting home/search/detail/player or any site's playback as
working. P3 sandbox/egress review, the pure-JVM loader, real JS/Python adapters,
representative corpus, physical Apple validation and P6 distribution remain open.
