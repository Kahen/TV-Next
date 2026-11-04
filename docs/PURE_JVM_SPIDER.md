# Approved pure-JVM Spider contract slice

Reference: FongMi/TV `123cc086159b0f13bf54bdf64bacbc259ca47c88`,
`catvod/.../crawler/Spider.java`. This module loads a separate JAR and invokes
the original media-method signatures. It is distinct from the existing fixed
`ProviderSpi` fixture. It is a host CLI/Docker harness, not an enabled HTTP
provider service or arbitrary JAR upload feature.

## Supported contract

| RPC v2 method | Actual Java invocation |
| --- | --- |
| initialization | Set `siteKey`, then `init(null, extend)` |
| home | `homeContent(boolean)`; merge `homeVideoContent().list` when needed |
| category | `categoryContent(String tid, String page, boolean filter, HashMap<String,String> extend)` |
| detail | `detailContent(List<String> ids)` |
| search | Overridden three-argument paged `searchContent`, otherwise legacy two-argument search on page 1; unsupported pagination fails explicitly |
| player | `playerContent(String flag, String opaqueId, List<String> vipFlags)` |
| cleanup | Attempt `destroy()` and close the provider classloader, including exceptional invocation; cleanup failure cannot report success |

The host supplies a small binary-signature compatibility class for that subset.
`android.content.Context` is an abstract signature token with no Android SDK
methods; no instance is ever supplied. Android `net/local/js/dialog`, Activity,
WebView, proxy/action/danmaku callbacks, JNI and other host APIs are absent.
The strict static preflight still rejects Android references in provider JARs,
including Context-dependent overrides. The owned reference inherits the base
no-op init method and uses only JDK APIs. A JAR that needs Android initialization
or upstream helper fields is not compatible with this subset.

## Artifact and process boundary

Only `owned-reference` is selectable normally. Sources are original TV-Next GPL
fixtures committed under `services/spider-runtime/jvm-spider/fixtures`; no
third-party provider binary or streaming source is bundled. The pinned JDK image
compiles a deterministic-timestamp provider JAR. A separate Python build stage
performs the existing bounded nonexecuting archive/bytecode preflight and rejects
host/platform package shadows. It emits an image-owned SHA-256 manifest. The
worker verifies those exact JAR bytes before class initialization on every run.
That manifest establishes correspondence to this trusted build, not independent
approval of any external provider. External activation would need an independently
reviewed registry/provenance policy and corpus, and remains disabled.

The classloader shares the host Spider contract but does not inherit the worker's
application classpath. It is dependency isolation, **not** a Java security sandbox:
reflection/JDK APIs and a determined provider cannot be contained by a classloader
alone. The existing OS container is the boundary: no network, non-root, read-only
root, no host mounts/socket, cap-drop/no-new-privileges, 128 MiB memory/32 PIDs,
CPU/FD/wall-time/input/output limits and confirmed teardown. No core API credential
enters the process. Provider System.out/System.err are discarded; errors use fixed
codes and do not serialize provider exceptions or reflection targets.

Request/response JSON is version **2**, separate from the unchanged three static
fixture workers' version 1. Inputs are bounded strict UTF-8, duplicate keys and
unknown top-level fields fail; class/path/image/URL selection is never accepted.
Runtime parameters such as IDs and filter values remain data. Raw FongMi Result
objects are returned; no network fetching, parser resolution or API normalization
is inferred from that result. The core API has no Docker socket or new endpoint.

## Reproduce and acceptance

```bash
docker build -f services/spider-runtime/jvm-spider/Dockerfile \
  -t tvnext/spider-jvm-approved:ci services/spider-runtime
cd services/spider-runtime
python3 -m unittest -v test_jvm_spider
```

The suite really loads the owned compiled JAR inside one constrained container
per invocation. It checks five signatures/opaque arguments, home fallback and
search overloads, unknown inputs/registry IDs, version/UTF-8 bounds, hash/preflight
evidence, stdout/error redaction, cleanup errors, timeout/OOM/process pressure,
network/filesystem/cgroup/host-secret and classpath observations. Owned negative
provider variants require explicit diagnostic mode in both host and worker.
Malformed ZIP/Android/JNI/path/native preflight regressions remain in the existing
`test_jar_inspect` suite. Full final-head CI is required; a passing owned corpus is
not representative third-party compatibility or an independent escape audit.

Remaining in #45/#4: an approved external pure-JVM corpus and dependency policy,
independent review, authorized host dispatcher/API activation, controlled network
egress, real JS/QuickJS/Python adapters and stateful/provider callbacks. The supplied
subscription's DEX/ARM-native package still requires the separate Android host.
