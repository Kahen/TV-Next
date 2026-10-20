"""Docker-backed isolation, parity, error and timeout tests (unittest only)."""
from __future__ import annotations

import os
import subprocess
import unittest
from runner import (
    IMAGES, RuntimeFailure, RuntimeTimeout,
    docker_command, run_fixture,
)


class FixtureIsolationTests(unittest.TestCase):
    def test_policy_has_no_network_mounts_or_host_privileges(self):
        for runtime in IMAGES:
            cmd = docker_command(runtime, "tvnext-fixture-test")
            parts = " ".join(cmd)
            for token in (
                "--network none", "--cap-drop ALL", "--security-opt no-new-privileges",
                "--read-only", "--pids-limit 32", "--memory 128m",
                "--memory-swap 128m", "--cpus 0.5", "--user 65534:65534",
                "--tmpfs /tmp:rw,nosuid,noexec,size=8m",
                "--log-driver none"
            ):
                self.assertIn(token, parts)
            for forbidden in ("--privileged", "--network host", "-v /", "--volume",
                              "docker.sock", "--pid host"):
                self.assertNotIn(forbidden, parts)

    def test_same_provider_contract_for_js_and_python(self):
        actions = [
            ("home", {}),
            ("category", {"categoryId": "movie"}),
            ("search", {"query": "series"}),
            ("detail", {"vodId": "movie-1"}),
            ("player", {"vodId": "movie-1", "episodeIndex": 0})
        ]
        for method, args in actions:
            with self.subTest(method=method):
                node = run_fixture("node", method, args).data
                python = run_fixture("python", method, args).data
                self.assertEqual(node, python)
                if method == "home":
                    self.assertEqual(len(node["items"]), 2)
                if method == "player":
                    self.assertEqual(node["url"], "https://example.org/fixture.mp4")

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
