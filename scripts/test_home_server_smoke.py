"""Bounded WebSocket receiver readiness polling; no network or media dependencies."""
import unittest
from unittest.mock import patch

import home_server_smoke as smoke


class RemoteReadinessTests(unittest.TestCase):
    def test_waits_until_own_device_is_online(self):
        snapshots = [
            [{"id": "other", "online": True}, {"id": "ours", "online": False}],
            [{"id": "ours", "online": True}],
        ]
        with patch.object(smoke, "request", side_effect=snapshots) as fetch, patch.object(smoke.time, "sleep") as sleep:
            smoke.wait_remote_receiver("fixture-token", "ours", attempts=3, delay=0.01)
        self.assertEqual(fetch.call_count, 2)
        fetch.assert_called_with("remote/devices", token="fixture-token")
        sleep.assert_called_once_with(0.01)

    def test_fails_when_receiver_never_registers(self):
        with patch.object(smoke, "request", return_value=[{"id": "ours", "online": False}]) as fetch, patch.object(smoke.time, "sleep") as sleep:
            with self.assertRaisesRegex(AssertionError, "never became online"):
                smoke.wait_remote_receiver("fixture-token", "ours", attempts=2, delay=0)
        self.assertEqual(fetch.call_count, 2)
        self.assertEqual(sleep.call_count, 2)

    def test_immediately_online_needs_no_sleep(self):
        with patch.object(smoke, "request", return_value=[{"id": "ours", "online": True}]), patch.object(smoke.time, "sleep") as sleep:
            smoke.wait_remote_receiver("fixture-token", "ours", attempts=2)
        sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
