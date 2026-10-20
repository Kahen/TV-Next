"""Host-side one-shot Docker isolation harness for *bundled* Spider fixtures only.

Not a service endpoint: do not expose arbitrary user code, image names or URLs.
Sandbox policy is enforced by the Docker host, NEVER by JS vm or Python eval.
"""
from __future__ import annotations

import json
import os
import resource
import subprocess
import tempfile
import uuid
from dataclasses import dataclass
from typing import Any

IMAGES = {
    "node": "tvnext/spider-node-fixture:ci",
    "python": "tvnext/spider-python-fixture:ci",
}
METHODS = frozenset({"home", "category", "search", "detail", "player"})
DIAGNOSTICS = frozenset({"__probe_network", "__probe_write", "__probe_policy", "__sleep"})
MAX_INPUT = 16_384
MAX_OUTPUT = 16_384
MAX_STDIO_FILE = 65_536


class RuntimeFailure(RuntimeError):
    """A bounded, redacted external runtime failure."""


class RuntimeTimeout(RuntimeFailure):
    pass


@dataclass(frozen=True)
class RuntimeResponse:
    runtime: str
    method: str
    data: dict[str, Any]


def docker_command(runtime: str, name: str, diagnostic: bool = False) -> list[str]:
    """No user-controlled image, mount, network, UID, cap or command in this list."""
    if runtime not in IMAGES:
        raise ValueError("unsupported runtime")
    cmd = [
        "docker", "run", "--rm", "--name", name,
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
    return cmd + [IMAGES[runtime]]


def _limit_host_output() -> None:
    # Cap files used for Docker CLI stdout/stderr to prevent runaway host-disk writes.
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_STDIO_FILE, MAX_STDIO_FILE))


def run_fixture(
    runtime: str, method: str, args: dict[str, Any] | None = None,
    timeout: float = 7.0, *, diagnostic: bool = False
) -> RuntimeResponse:
    if runtime not in IMAGES:
        raise ValueError("unsupported runtime")
    if method not in (DIAGNOSTICS if diagnostic else METHODS):
        raise ValueError("method is not allowed for this mode")
    if args is None:
        args = {}
    if not isinstance(args, dict):
        raise ValueError("args must be a JSON object")
    if not 0.1 <= timeout <= 20:
        raise ValueError("timeout outside configured limits")
    wire = json.dumps({"version": 1, "method": method, "args": args},
                      ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(wire) > MAX_INPUT:
        raise ValueError("request too large")
    name = "tvnext-fixture-" + uuid.uuid4().hex[:20]
    command = docker_command(runtime, name, diagnostic=diagnostic)
    try:
        with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
            try:
                completed = subprocess.run(
                    command, input=wire, stdout=stdout_file, stderr=stderr_file,
                    timeout=timeout, check=False, preexec_fn=_limit_host_output,
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
                    result.get("version") != 1 or result.get("runtime") != runtime or
                    not isinstance(result.get("data"), dict)):
                raise RuntimeFailure("unexpected response schema")
            return RuntimeResponse(runtime=runtime, method=method, data=result["data"])
    except FileNotFoundError as exc:
        raise RuntimeFailure("Docker CLI unavailable") from exc
    finally:
        # --rm normally removes successful runs. A timed-out docker client may
        # leave its container alive; always explicitly force-remove by unique name.
        try:
            subprocess.run(
                ["docker", "rm", "-f", name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=8, check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            # Do not replace the original runtime failure with cleanup noise.
            pass
