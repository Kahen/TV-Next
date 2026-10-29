"""Host-side one-shot Docker isolation harness for *bundled* Spider fixtures only.

Not a service endpoint: do not expose arbitrary user code, image names or URLs.
Sandbox policy is enforced by the Docker host, NEVER by JS vm or Python eval.
"""
from __future__ import annotations

import json
import os
import resource
import re
import subprocess
import tempfile
import time
import uuid
from dataclasses import dataclass
from typing import Any

IMAGES = {
    "node": "tvnext/spider-node-fixture:ci",
    "python": "tvnext/spider-python-fixture:ci",
    "java": "tvnext/spider-java-fixture:ci",
}
APPROVED_IMAGES = {"java-spider": "tvnext/spider-jvm-approved:ci"}
APPROVED_PROVIDER = "owned-reference"
APPROVED_TEST_PROVIDERS = frozenset({
    "owned-paged", "owned-fallback", "owned-throwing", "owned-invalid", "owned-cleanup",
    "owned-timeout", "owned-output", "owned-oom", "owned-processes", "owned-policy",
})
METHODS = frozenset({"home", "category", "search", "detail", "player"})
DIAGNOSTICS = frozenset({"__probe_network", "__probe_write", "__probe_policy", "__probe_output", "__crash", "__sleep"})
MAX_INPUT = 16_384
MAX_OUTPUT = 16_384
MAX_STDIO_FILE = 65_536


class RuntimeFailure(RuntimeError):
    """A bounded, redacted external runtime failure."""


class RuntimeTimeout(RuntimeFailure):
    pass


class RuntimeCleanupFailure(RuntimeFailure):
    """The caller must stop reusing this Docker host until cleanup is confirmed."""


@dataclass(frozen=True)
class RuntimeResponse:
    runtime: str
    method: str
    data: dict[str, Any]


def docker_command(runtime: str, name: str, diagnostic: bool = False) -> list[str]:
    """No user-controlled image, mount, network, UID, cap or command in this list."""
    images = IMAGES | APPROVED_IMAGES
    if runtime not in images:
        raise ValueError("unsupported runtime")
    cmd = [
        "docker", "run", "--rm", "--pull", "never", "--name", name,
        "--network", "none",
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "--read-only",
        "--pids-limit", "32",
        "--memory", "128m",
        "--memory-swap", "128m",
        "--cpus", "0.5",
        "--user", "65534:65534",
        "--tmpfs", "/tmp:rw,nosuid,noexec,size=8m",
        "--ulimit", "nofile=64:64",
        "--log-driver", "none",
        "--attach", "stdin", "--attach", "stdout", "--attach", "stderr",
        "--interactive",
    ]
    if diagnostic:
        cmd += ["--env", "TVNEXT_TEST_HOOKS=1"]
    return cmd + [images[runtime]]


def _limit_host_output() -> None:
    # Cap files used for Docker CLI stdout/stderr to prevent runaway host-disk writes.
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_STDIO_FILE, MAX_STDIO_FILE))


def docker_create_command(runtime: str, name: str, diagnostic: bool = False) -> list[str]:
    """Register the constrained container before asking Docker to start it."""
    original = docker_command(runtime, name, diagnostic)
    result = ["docker", "create"]
    index = 2
    while index < len(original):
        if original[index] == "--rm":
            index += 1
        elif original[index] == "--attach":
            index += 2
        else:
            result.append(original[index])
            index += 1
    return result


def _remove_container(name: str, *, pending_creation: bool = False, budget: float = 20.0) -> bool:
    """A successful rm CLI invocation is not proof that asynchronous removal ended.

    A timed-out create request can commit after its client dies. In that case
    absence is accepted only after observing/removing that unique container.
    Daemon errors are unknown state, never evidence of absence.
    """
    deadline = time.monotonic() + budget
    observed = not pending_creation
    while time.monotonic() < deadline:
        try:
            removed = subprocess.run(["docker", "rm", "-f", name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=min(2.0, max(0.01, deadline-time.monotonic())), check=False)
            observed = observed or removed.returncode == 0
            if time.monotonic() >= deadline:
                break
            remaining = subprocess.run(["docker", "ps", "-aq", "--filter", "name=^/"+name+"$"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                timeout=min(2.0, max(0.01, deadline-time.monotonic())), check=False)
            if remaining.returncode == 0:
                if remaining.stdout.strip():
                    observed = True
                elif observed:
                    return True
        except (OSError, subprocess.TimeoutExpired):
            pass
        time.sleep(min(0.1, max(0, deadline-time.monotonic())))
    return False


def _run_runtime(
    runtime: str, method: str, args: dict[str, Any] | None = None,
    timeout: float = 7.0, *, diagnostic: bool = False, version: int = 1,
    provider: str | None = None,
) -> RuntimeResponse:
    if runtime not in (IMAGES if version == 1 else APPROVED_IMAGES):
        raise ValueError("unsupported runtime")
    if method not in (DIAGNOSTICS if diagnostic and version == 1 else METHODS):
        raise ValueError("method is not allowed for this mode")
    if args is None:
        args = {}
    if not isinstance(args, dict):
        raise ValueError("args must be a JSON object")
    if not 0.1 <= timeout <= 20:
        raise ValueError("timeout outside configured limits")
    request = {"version": version, "method": method, "args": args}
    if version == 2:
        request["provider"] = provider
    wire = json.dumps(request,
                      ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(wire) > MAX_INPUT:
        raise ValueError("request too large")
    name = "tvnext-fixture-" + uuid.uuid4().hex[:20]
    command = docker_create_command(runtime, name, diagnostic=diagnostic)
    deadline = time.monotonic()+timeout
    pending_creation = False
    cleanup_needed = True
    try:
        with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
            try:
                pending_creation = True
                created = subprocess.run(command, stdout=stdout_file, stderr=stderr_file,
                    timeout=max(0.001,deadline-time.monotonic()), check=False, preexec_fn=_limit_host_output)
                if created.returncode != 0:
                    raise RuntimeFailure("runtime container creation failed")
                stdout_file.seek(0)
                identity = stdout_file.read(100).strip()
                if not re.fullmatch(rb"[a-f0-9]{64}",identity):
                    raise RuntimeFailure("invalid container identity")
                pending_creation = False
                stdout_file.seek(0); stdout_file.truncate()
                stderr_file.seek(0); stderr_file.truncate()
                remaining = deadline-time.monotonic()
                if remaining <= 0:
                    raise RuntimeTimeout("runtime exceeded wall-clock timeout")
                completed = subprocess.run(
                    ["docker", "start", "--attach", "--interactive", name],
                    input=wire, stdout=stdout_file, stderr=stderr_file,
                    timeout=remaining, check=False, preexec_fn=_limit_host_output,
                )
            except subprocess.TimeoutExpired as exc:
                raise RuntimeTimeout("runtime exceeded wall-clock timeout") from exc
            if stdout_file.tell() > MAX_OUTPUT or stderr_file.tell() > MAX_STDIO_FILE:
                raise RuntimeFailure("runtime output limit exceeded")
            stdout_file.seek(0)
            payload = stdout_file.read(MAX_OUTPUT + 1)
            if len(payload) > MAX_OUTPUT:
                raise RuntimeFailure("runtime output limit exceeded")
            if completed.returncode != 0:
                try:
                    detail = json.loads(payload.decode("utf-8"))
                    code = detail.get("code", "nonzero-exit")
                    if not isinstance(code, str) or len(code) > 80:
                        code = "nonzero-exit"
                except (ValueError, UnicodeDecodeError, AttributeError):
                    code = "nonzero-exit"
                raise RuntimeFailure("runtime rejected request: " + code)
            try:
                result = json.loads(payload.decode("utf-8"))
            except (ValueError, UnicodeDecodeError) as exc:
                raise RuntimeFailure("invalid runtime response") from exc
            if (not isinstance(result, dict) or result.get("status") != "ok" or
                    result.get("version") != version or result.get("runtime") != runtime or
                    not isinstance(result.get("data"), dict)):
                raise RuntimeFailure("unexpected response schema")
            return RuntimeResponse(runtime=runtime, method=method, data=result["data"])
    except FileNotFoundError as exc:
        # If create itself could not exec, no Docker transaction started. If the
        # CLI disappears after registration, the known container still needs cleanup.
        cleanup_needed = not pending_creation
        raise RuntimeFailure("Docker CLI unavailable") from exc
    finally:
        if cleanup_needed and not _remove_container(name,pending_creation=pending_creation):
            # Preserve any original timeout/failure as __context__, but never report
            # an ordinary success or clean timeout when resource teardown is unknown.
            raise RuntimeCleanupFailure("runtime container removal could not be confirmed")


def run_fixture(runtime: str, method: str, args: dict[str, Any] | None = None,
                timeout: float = 7.0, *, diagnostic: bool = False) -> RuntimeResponse:
    """Original static fixture v1 entry point; no JAR activation is inferred."""
    return _run_runtime(runtime, method, args, timeout, diagnostic=diagnostic)


def run_approved_spider(method: str, args: dict[str, Any] | None = None,
                        timeout: float = 7.0, *, provider: str = APPROVED_PROVIDER,
                        diagnostic: bool = False) -> RuntimeResponse:
    """Owned/pinned JVM contract corpus only. No caller path, class, image or URL.

    Remains a host-side CLI harness, not an API endpoint. Diagnostic provider
    variants must be enabled explicitly at both host and worker boundaries.
    """
    if provider != APPROVED_PROVIDER and not (diagnostic and provider in APPROVED_TEST_PROVIDERS):
        raise ValueError("provider is not approved")
    return _run_runtime("java-spider", method, args, timeout, diagnostic=diagnostic,
                        version=2, provider=provider)
