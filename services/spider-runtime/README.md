# P3 — Bundled fixture runtime isolation (experimental)

**Scope limitation:** This is an operating-system isolation prototype for two reviewable, in-repo fixture workers (Node.js and Python), **not an arbitrary Spider plugin runtime**. It does not download code, execute user-supplied scripts, fetch URLs, talk to an external site, or implement FongMi Android SDK APIs. There is no network API route to the runner. It is not part of production Compose and must not be exposed publicly.

## Architecture / contract

- Host-only `runner.py` accepts one of two **hardcoded Docker image tags** and five allowed read-only methods: `home`, `category`, `search`, `detail`, `player`.
- Single JSON RPC v1 request on stdin: `{"version":1,"method":"home","args":{}}`. Single JSON result on stdout: `{"version":1,"status":"ok","runtime":"node","data":{...}}`. Errors return bounded `{"version":1,"status":"error","code":"..." }` without stack traces, secrets, or raw plugin output.
- Both workers read the same committed `fixtures/catalog.json` and must provide **identical business results**, independent of language. URL strings are placeholder fixture metadata; no runtime fetch occurs.
- Host launch is a one-shot Docker process **per invocation**. The launch policy disallows networking, Docker socket mounts, host mounts, Linux capabilities, writable root filesystems and root UID.
- JS and Python have diagnostic test hooks for controlled network, filesystem and timeout probes, enabled only by a host-side explicit `diagnostic=True` test invocation; the normal caller rejects their methods. The hooks are **not** plugin APIs.

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
| Time budget | Configurable 0.1–20 s, 7 s default; Docker container force-removed on timeout |
| Images | Fixed in source; no user-provided image, source path or shell command |

Docker's host daemon is a **privileged trust boundary**. Do not mount a Docker socket inside the API, expose the host Python runner through REST, rely on JS `vm` or Python `eval` as a security boundary, or connect a live plugin loader until a security review validates Docker daemon access, UID namespaces, seccomp/LSM policy, OS updates, cgroup limits, network egress controls, log/secret isolation, and allowed fixture provenance. `--network none` proves egress deny in CI, but also means *real Spider plugins requiring Internet cannot function yet*.

## Reproduce isolation tests (Linux with Docker)

```bash
docker build -f services/spider-runtime/node/Dockerfile -t tvnext/spider-node-fixture:ci services/spider-runtime
docker build -f services/spider-runtime/python/Dockerfile -t tvnext/spider-python-fixture:ci services/spider-runtime
cd services/spider-runtime
python3 -m unittest -v test_runtime
```

GitHub Actions `.github/workflows/spider-sandbox.yml` executes the same tests on a disposable hosted Ubuntu runner. Tests require Docker and Python 3.12; they start one isolated container per operation and remove every container afterward.

## Verified and unverified

The suite checks five method responses and JS/Python parity; malformed action and oversized input handling; blocked outbound TCP; rejected attempts to write under `/worker`; live cgroup CPU/memory/PID quotas, non-root UID and host-environment-secret isolation; wall-clock timeout and leaked container cleanup; and checks explicit Docker hardening flags.

**Not implemented / not proven:** Java/JAR Android-free adapter, real Spider callback APIs, arbitrary JS/Python code execution, plugin dependency installation, QuickJS compatibility, network allowlist logic, end-user authorization, full control-plane/API integration, Linux container escape resistance, independent security audit, native iOS Spider parity, or real provider fixture corpus. Any future transition to dynamic plugins requires a new reviewed architecture and complete P3 acceptance tests.
