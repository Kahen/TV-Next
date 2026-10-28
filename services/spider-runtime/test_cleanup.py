"""Host lifecycle regressions; deterministic fake Docker/clock, no Docker required."""
import json
import subprocess
import unittest
from unittest.mock import patch
import runner


class Clock:
    def __init__(self): self.value=0.0
    def now(self): return self.value
    def sleep(self,delay): self.value+=delay


class CleanupTests(unittest.TestCase):
    def removal(self,sequence,pending=False):
        clock=Clock()
        with patch.object(runner.time,"monotonic",clock.now), patch.object(runner.time,"sleep",clock.sleep), patch.object(runner.subprocess,"run",side_effect=sequence):
            return runner._remove_container("tvnext-fixture-"+"a"*20,pending_creation=pending,budget=0.3)

    def result(self,code=0,output=b""):
        return subprocess.CompletedProcess([],code,output)

    def test_removal_in_progress_is_polled_until_container_is_absent(self):
        self.assertTrue(self.removal([
            self.result(1),self.result(0,b"container-id\n"),
            self.result(1),self.result(0,b"container-id\n"),
            self.result(),self.result(),
        ]))

    def test_daemon_failure_and_persistent_container_are_not_success(self):
        self.assertFalse(self.removal([self.result(1)]*6))
        self.assertFalse(self.removal([self.result(),self.result(0,b"present")]*3))

    def test_late_create_cannot_be_mistaken_for_already_removed(self):
        self.assertTrue(self.removal([
            self.result(1),self.result(),
            self.result(1),self.result(0,b"late-created"),
            self.result(),self.result(),
        ],pending=True))
        self.assertFalse(self.removal([self.result(1),self.result()]*3,pending=True))

    def test_cleanup_subprocess_timeout_is_bounded_and_retried(self):
        self.assertTrue(self.removal([
            subprocess.TimeoutExpired(["docker","rm"],2),self.result(),self.result(),
        ]))

    def invoke(self,failure=None,cleanup=True,invalid_identity=False):
        calls=[]
        def docker(command,**kwargs):
            calls.append(command)
            if command[1]=="create":
                kwargs["stdout"].write(b"bad\n" if invalid_identity else b"a"*64+b"\n")
                return self.result()
            if failure: raise failure
            kwargs["stdout"].write(json.dumps({"version":1,"status":"ok","runtime":"node","data":{"items":[]}}).encode())
            return self.result()
        with patch.object(runner.subprocess,"run",side_effect=docker), patch.object(runner,"_remove_container",return_value=cleanup) as remove:
            result=runner.run_fixture("node","home")
            return result,calls,remove.call_args

    def test_registered_identity_precedes_start_and_keeps_the_hardening_policy(self):
        result,calls,cleanup=self.invoke()
        self.assertEqual(result.data,{"items":[]})
        self.assertEqual(calls[0][:2],["docker","create"])
        self.assertIn("--pull",calls[0]);self.assertIn("never",calls[0])
        self.assertIn("--read-only",calls[0]);self.assertIn("--memory",calls[0])
        self.assertEqual(calls[1][:4],["docker","start","--attach","--interactive"])
        self.assertFalse(cleanup.kwargs["pending_creation"])

    def test_unconfirmed_cleanup_overrides_success_and_preserves_timeout_context(self):
        with self.assertRaises(runner.RuntimeCleanupFailure): self.invoke(cleanup=False)
        with self.assertRaises(runner.RuntimeCleanupFailure) as error:
            self.invoke(subprocess.TimeoutExpired(["docker","start"],1),cleanup=False)
        self.assertIsInstance(error.exception.__context__,runner.RuntimeTimeout)

    def test_worker_timeout_stays_a_timeout_after_confirmed_cleanup(self):
        with self.assertRaises(runner.RuntimeTimeout):
            self.invoke(subprocess.TimeoutExpired(["docker","start"],1))

    def test_invalid_daemon_identity_never_starts_the_worker(self):
        with self.assertRaisesRegex(runner.RuntimeFailure,"identity"):
            self.invoke(invalid_identity=True)

    def test_timed_out_create_keeps_late_creation_state_until_teardown(self):
        with patch.object(runner.subprocess,"run",side_effect=subprocess.TimeoutExpired(["docker","create"],1)), patch.object(runner,"_remove_container",return_value=True) as remove:
            with self.assertRaises(runner.RuntimeTimeout): runner.run_fixture("node","home")
            self.assertTrue(remove.call_args.kwargs["pending_creation"])

    def test_missing_cli_before_registration_has_no_container_to_clean(self):
        with patch.object(runner.subprocess,"run",side_effect=FileNotFoundError()), patch.object(runner,"_remove_container") as remove:
            with self.assertRaisesRegex(runner.RuntimeFailure,"CLI unavailable"): runner.run_fixture("node","home")
            remove.assert_not_called()

    def test_missing_cli_after_registration_cannot_silently_leave_container(self):
        with self.assertRaises(runner.RuntimeCleanupFailure): self.invoke(FileNotFoundError(),cleanup=False)


if __name__ == "__main__": unittest.main()
