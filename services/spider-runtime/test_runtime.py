"""Docker-backed isolation, parity, error and timeout tests (unittest only)."""
from __future__ import annotations

import json
import os
import subprocess
import unittest
import uuid
from runner import (
    IMAGES, RuntimeFailure, RuntimeTimeout,
    docker_command, docker_create_command, run_fixture,
)


class FixtureIsolationTests(unittest.TestCase):
    def test_policy_has_no_network_mounts_or_host_privileges(self):
        for runtime in IMAGES:
            create = " ".join(docker_create_command(runtime,"tvnext-fixture-test"))
            for token in ("--pull never","--network none","--read-only","--cap-drop ALL",
                          "--security-opt no-new-privileges","--user 65534:65534",
                          "--memory 128m","--pids-limit 32","--cpus 0.5","--log-driver none"):
                self.assertIn(token,create)
            self.assertNotIn("--attach",create)
            self.assertNotIn("--rm",create)
        for runtime in IMAGES:
            cmd = docker_command(runtime, "tvnext-fixture-test")
            parts = " ".join(cmd)
            for token in (
                "--pull never", "--network none", "--cap-drop ALL", "--security-opt no-new-privileges",
                "--read-only", "--pids-limit 32", "--memory 128m",
                "--memory-swap 128m", "--cpus 0.5", "--user 65534:65534",
                "--tmpfs /tmp:rw,nosuid,noexec,size=8m",
                "--log-driver none"
            ):
                self.assertIn(token, parts)
            for forbidden in ("--privileged", "--network host", "-v /", "--volume",
                              "docker.sock", "--pid host"):
                self.assertNotIn(forbidden, parts)

    def test_same_provider_contract_for_all_three_runtimes(self):
        actions = [
            ("home", {}),
            ("category", {"categoryId": "movie"}),
            ("search", {"query": "series"}),
            ("detail", {"vodId": "movie-1"}),
            ("player", {"vodId": "movie-1", "episodeIndex": 0})
        ]
        for method, args in actions:
            with self.subTest(method=method):
                responses = {
                    runtime: run_fixture(runtime, method, args).data
                    for runtime in IMAGES
                }
                self.assertEqual(responses["node"], responses["python"])
                self.assertEqual(responses["node"], responses["java"])
                result = responses["java"]
                if method == "home":
                    self.assertEqual(len(result["items"]), 2)
                if method == "player":
                    self.assertEqual(result["url"], "https://example.org/fixture.mp4")

    def test_java_jar_rejects_malformed_wire_and_duplicate_json_keys(self):
        malformed_requests = [
            b"not JSON",
            b'{"version":1,"method":"home","args":{},"method":"player"}',
            b'{"version":1,"method":"home","args":{"null_key":null,"null_key":true}}',
            b'{"version":1,"method":"home","args":[]}',
            b'{"version":1.0,"method":"home","args":{}}',
            b'{"version":1,"method":"home","args":{}}' + b" " * 17000,
        ]
        for raw in malformed_requests:
            name = "tvnext-fixture-" + uuid.uuid4().hex[:20]
            with self.subTest(request=raw[:65]):
                run = subprocess.run(
                    docker_command("java", name),
                    input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    timeout=9, check=False
                )
                self.assertEqual(run.returncode, 2, run.stderr[:500])
                self.assertLess(len(run.stdout), 1000)
                result = json.loads(run.stdout)
                self.assertEqual(result["version"], 1)
                self.assertEqual(result["status"], "error")
                self.assertIn(result["code"], ("invalid-input", "invalid-request", "request-too-large"))
                self.assertNotIn("Exception", run.stdout.decode("utf8"))

    def test_allows_no_arbitrary_methods_images_or_user_source(self):
        for runtime in IMAGES:
            with self.subTest(runtime=runtime):
                with self.assertRaises(ValueError):
                    run_fixture(runtime, "__probe_network", {})
                with self.assertRaises(ValueError):
                    run_fixture(runtime, "eval", {"code": "process.exit(1)"})
                with self.assertRaises(RuntimeFailure):
                    run_fixture(runtime, "detail", {"vodId": "missing"})
                with self.assertRaises(ValueError):
                    run_fixture(runtime, "home", {"a": "x" * 16_384})
                with self.assertRaises(RuntimeFailure):
                    run_fixture(runtime, "search", {})
        with self.assertRaises(ValueError):
            run_fixture("arbitrary/image", "home", {})

    def test_container_cannot_write_worker_tree_or_access_network(self):
        for runtime in IMAGES:
            with self.subTest(runtime=runtime):
                output = run_fixture(runtime, "__probe_write", diagnostic=True).data
                self.assertTrue(output["readonly"])
                net = run_fixture(runtime, "__probe_network", diagnostic=True).data
                self.assertEqual(net["network"], "blocked")

    def test_cgroup_quotas_nonroot_uid_and_secret_boundary(self):
        original = os.environ.get("TVNEXT_HOST_SECRET_TEST")
        os.environ["TVNEXT_HOST_SECRET_TEST"] = "host-secret-never-forward"
        try:
            for runtime in IMAGES:
                with self.subTest(runtime=runtime):
                    probe = run_fixture(runtime, "__probe_policy", diagnostic=True).data
                    self.assertEqual(probe["uid"], 65534)
                    self.assertFalse(probe["hostSecretVisible"])
                    # Linux GitHub runners use cgroup v2; don't infer quotas from CLI args alone.
                    self.assertIsNotNone(probe["memoryMax"], "memory cgroup missing")
                    self.assertLessEqual(int(probe["memoryMax"]), 128 * 1024 * 1024)
                    self.assertLessEqual(int(probe["pidsMax"]), 32)
                    quota, period = map(int, probe["cpuMax"].split())
                    self.assertLessEqual(quota / period, 0.5)
        finally:
            if original is None:
                del os.environ["TVNEXT_HOST_SECRET_TEST"]
            else:
                os.environ["TVNEXT_HOST_SECRET_TEST"] = original

    def test_output_flood_and_unexpected_worker_crash_are_contained(self):
        for runtime in IMAGES:
            with self.subTest(runtime=runtime):
                with self.assertRaisesRegex(RuntimeFailure, "output limit exceeded"):
                    run_fixture(runtime, "__probe_output", diagnostic=True)
                with self.assertRaisesRegex(RuntimeFailure, "nonzero-exit"):
                    run_fixture(runtime, "__crash", diagnostic=True)

    def test_wall_clock_timeout_kills_container(self):
        for runtime in IMAGES:
            with self.subTest(runtime=runtime):
                with self.assertRaises(RuntimeTimeout):
                    run_fixture(runtime, "__sleep", diagnostic=True, timeout=1.5)
        containers = subprocess.check_output(
            ["docker", "ps", "-aq", "--filter", "name=tvnext-fixture-"],
            text=True, timeout=5,
        ).strip()
        self.assertEqual(containers, "", "timed-out runtime container leaked")


if __name__ == "__main__":
    unittest.main(verbosity=2)
