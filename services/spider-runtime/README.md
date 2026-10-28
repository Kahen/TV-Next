# P3 — Bundled fixture runtime isolation (experimental)

The API also has a separate, default-off [Android Spider bridge](../../docs/ANDROID_SPIDER_BRIDGE.md)
for exact administrator-approved `csp_*` init bindings on an existing FongMi
Android host. It does not alter this Docker fixture harness or make DEX/native
plugins executable in a JVM. Real ARM-host verification remains pending.

**Scope limitation:** This is an operating-system isolation prototype for three reviewable, in-repo fixture workers (Node.js, Python and Java 21), **not an arbitrary Spider plugin runtime**. It does not download code, execute user-supplied scripts, fetch URLs, talk to an external site, or implement FongMi Android SDK APIs. There is no network API route to the runner. It is not part of production Compose and must not be exposed publicly.

## Architecture / contract

- Host-only `runner.py` accepts one of three **hardcoded Docker image tags** and five allowed read-only methods: `home`, `category`, `search`, `detail`, `player`.
- Single JSON RPC v1 request on stdin: `{"version":1,"method":"home","args":{}}`. Single JSON result on stdout: `{"version":1,"status":"ok","runtime":"node","data":{...}}`. Errors return bounded `{"version":1,"status":"error","code":"..." }` without stack traces, secrets, or raw plugin output.
- All workers read the same committed `fixtures/catalog.json` and must provide **identical business results**, independent of language. URL strings are placeholder fixture metadata; no runtime fetch occurs.
- Host launch is a one-shot Docker container **per invocation**, registered with `docker create` before `docker start --attach --interactive`. The launch policy disallows networking, Docker socket mounts, host mounts, Linux capabilities, writable root filesystems and root UID. Fixture images must exist locally (`--pull never`).
- JS, Python and Java have diagnostic test hooks for controlled network, filesystem and timeout probes, enabled only by a host-side explicit `diagnostic=True` test invocation; the normal caller rejects their methods. The hooks are **not** plugin APIs.

### Hardening controls (enforced by Docker CLI)

| Control | Policy |
| --- | --- |
| Network | `--network none`; no network namespace access to the host |
| UID / privileges | `--user 65534:65534 --cap-drop ALL --security-opt no-new-privileges` |
| Root filesystem | `--read-only`, only an 8 MiB `/tmp` tmpfs with `noexec,nosuid` |
| Memory | `--memory 128m --memory-swap 128m` |
| CPU | `--cpus 0.5` |
| Process / descriptors | `--pids-limit 32 --ulimit nofile=64:64` |
| Request / output | 16 KiB JSON request and response; 64 KiB host stdout/stderr file limits |
| Time budget | Configurable 0.1–20 s, 7 s default, shared by create/start/execution; separate bounded 20 s teardown confirmation |
| Images | Fixed in source; no user-provided image, source path or shell command |

Docker's host daemon is a **privileged trust boundary**. Do not mount a Docker socket inside the API, expose the host Python runner through REST, rely on JS `vm` or Python `eval` as a security boundary, or connect a live plugin loader until a security review validates Docker daemon access, UID namespaces, seccomp/LSM policy, OS updates, cgroup limits, network egress controls, log/secret isolation, and allowed fixture provenance. `--network none` proves egress deny in CI, but also means *real Spider plugins requiring Internet cannot function yet*.

## Reproduce isolation tests (Linux with Docker)

```bash
docker build -f services/spider-runtime/node/Dockerfile -t tvnext/spider-node-fixture:ci services/spider-runtime
docker build -f services/spider-runtime/python/Dockerfile -t tvnext/spider-python-fixture:ci services/spider-runtime
docker build -f services/spider-runtime/java/Dockerfile -t tvnext/spider-java-fixture:ci services/spider-runtime
cd services/spider-runtime
python3 -m unittest -v test_runtime
```

GitHub Actions `.github/workflows/spider-sandbox.yml` executes the same tests on a disposable hosted Ubuntu runner. Tests require Docker and Python 3.12; they start one isolated container per operation and remove every container afterward.

## Verified and unverified

The suite checks five method responses and Node/Python/Java parity; malformed action and oversized input handling; blocked outbound TCP; rejected attempts to write under `/worker`; live cgroup CPU/memory/PID quotas, non-root UID and host-environment-secret isolation; worker crash containment, oversized-output rejection, wall-clock timeout and leaked container cleanup; and checks explicit Docker hardening flags.

**Not implemented / not proven:** dynamic Java/JAR provider loading, pure JVM FongMi Spider adapters, Android-dependent JARs, real Spider callback APIs, arbitrary JS/Python code execution, plugin dependency installation, QuickJS compatibility, network allowlist logic, end-user authorization, full control-plane/API integration, Linux container escape resistance, independent security audit, native iOS Spider parity, or real provider fixture corpus. Any future transition to dynamic plugins requires a new reviewed architecture and complete P3 acceptance tests.


## Bundled JVM/JAR reference (this PR)

The `java/Dockerfile` image uses **Java 21**, compiles `Json.java` and `Worker.java` into `tvnext-fixture.jar` using the JDK `jar` tool, and runs it via `java -jar` in a separate unprivileged JRE Alpine container. The worker parses bounded JSON messages using a small local strict codec and reads only the same committed `fixtures/catalog.json` as the other runtimes. A multi-stage build keeps the Java compiler out of the runtime image.

**Security caveats:** This is an audited **static fixture JAR**. It does *not* accept arbitrary JAR bytecode, external dependencies, Android classes, JNI, dynamic `ClassLoader`, arbitrary reflection or third-party Spider callbacks. Calling this a full FongMi Java Spider adapter would be incorrect. A future separate milestone needs explicit Java SPI contracts, an allowlisted dependency policy, permitted test JARs, provenance checks, sandbox escape tests and rejection of Android-only implementations. No JAR loading endpoint exists in Spring Boot, Web or iOS.

## Pure JVM SPI and static JAR compatibility inspection

`ProviderSpi` is now the common Java implementation boundary, with `providerId()` and `handle(method,args,fixture)`. `BundledFixtureProvider` is the only implementation, selected through **fixed compile-time instantiation**. `Worker` handles the JSON wire, diagnostic probes and error redaction. No `ServiceLoader`, external JAR classpath, reflection, arbitrary class instantiation or runtime-selected provider is permitted.

To check an explicitly obtained JAR **without executing it**, use:

```bash
python3 services/spider-runtime/jar_inspect.py /path/to/authorized.jar
```

The local, read-only scanner checks archive size/ZIP path traversal/compression limits, class file structure, JVM constant pool/descriptors referencing `android/`, `dalvik/` and `androidx/`, JNI `native` method flags and bundled native libraries (`.so`, `.dll`, etc.). It produces machine-readable `pure-jvm-candidate`, `unsupported` or `rejected` statuses. Candidate means **not obviously Android-dependent by these heuristics**, NOT verified safe, functional or compatible. Reflection, JNI wrappers, classfile tricks, late-loaded dependencies and obfuscation may evade static identification. Both external provider activation and network access remain prohibited.

CI runs unit tests built from synthetic classfile bytes and scans the actual bundled JAR extracted without execution from the freshly built Docker image. P3 still requires an approved source corpus, dynamic plugin policy, full bytecode/security review, Android API test fixtures and an independent sandbox assessment before executing other JARs.


## Confirmed teardown and delayed Docker transactions

A CI run exposed a Docker start timeout followed by a container stuck in
`Created`/removal-in-progress. Killing a `docker run` client and issuing one
`docker rm -f` did not prove resource teardown. The runner now registers and
validates a container identity before starting it, shares the original execution
deadline across both phases, and retries removal/polls exact-name absence within
an additional 20-second cleanup budget. CPU, memory, PID and execution limits
are unchanged; automatic image pulling is disabled.

A timed-out create is treated as an outstanding daemon transaction. Absence is
accepted only after that unique container was observed or removed. Unreachable
daemons and unconfirmed removal raise `RuntimeCleanupFailure`, including after
an otherwise successful worker response; the original failure remains in the
exception context. A caller must stop using that Docker host until an operator
or host controller confirms cleanup. This module does not implement persistent
cross-process host quarantine and is still not a production runtime service.

`test_cleanup.py` uses a deterministic fake clock/CLI to cover delayed creation,
removal-in-progress, daemon failures, cleanup deadlines, lifecycle ordering,
missing CLI, preserved timeout context and refusing success after failed teardown.
The Docker integration suite still verifies live cgroups, all worker methods,
timeout cleanup and the final empty-container inventory. The execution deadline initiates termination; a stalled Docker daemon can still
prevent timely termination. Unconfirmed teardown is therefore a host failure,
not a sandbox guarantee or permission to continue serving requests.

Initial Docker integration evidence for the new lifecycle:
https://github.com/Kahen/TV-Next/actions/runs/40683953519 (same implementation;
subsequent documentation-only changes still require the final PR gates).
