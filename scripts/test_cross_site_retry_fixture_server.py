"""Regression tests for the owned iOS cross-site search fixture."""
import json
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from cross_site_retry_fixture_server import Handler


class CrossSiteRetryFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def get(self, path):
        with urlopen(self.base + path, timeout=3) as response:
            return json.load(response)

    def post(self, path, body):
        request = Request(self.base + path, data=json.dumps(body).encode(),
                          headers={"Content-Type": "application/json"})
        with urlopen(request, timeout=3) as response:
            return json.load(response)

    def test_success_failure_retry_and_original_query(self):
        self.get("/fixture/reset")
        document = self.post("/api/v1/subscriptions/load", {"content": "fixture", "url": ""})
        self.assertEqual([site["key"] for site in document["sites"]], ["b", "a", "b"])
        self.assertTrue(document["sites"][0]["hidden"])
        self.assertEqual(document["sites"][0]["name"], "Hidden Spoof")
        self.assertEqual([site["name"] for site in document["sites"] if not site["hidden"]],
                         ["Mirror", "Mirror"])
        a = self.post("/api/v1/subscriptions/search", {"siteKey": "a", "query": "original"})
        self.assertEqual(a["items"][0]["id"], "a-id")
        with self.assertRaises(HTTPError) as error:
            self.post("/api/v1/subscriptions/search", {"siteKey": "b", "query": "original"})
        self.assertEqual(error.exception.code, 503)
        b = self.post("/api/v1/subscriptions/search", {"siteKey": "b", "query": "original"})
        self.assertEqual(b["items"][0]["id"], "b-id")
        state = self.get("/fixture/state")
        self.assertEqual(state["counts"], {"a": 1, "b": 2})
        self.assertEqual({q["query"] for q in state["queries"]}, {"original"})

    def test_successful_empty_search_is_not_a_transport_failure(self):
        self.get("/fixture/reset")
        for key in ("a", "b"):
            result = self.post("/api/v1/subscriptions/search",
                               {"siteKey": key, "query": "no-results"})
            self.assertEqual(result["items"], [])
            self.assertEqual(result["total"], 0)
            self.assertFalse(result["hasMore"])
        state = self.get("/fixture/state")
        self.assertEqual(state["counts"], {"a": 1, "b": 1})

    def test_reject_unknown_and_oversized(self):
        self.get("/fixture/reset")
        with self.assertRaises(HTTPError) as error:
            self.post("/api/v1/subscriptions/search", {"siteKey": "other", "query": "x"})
        self.assertEqual(error.exception.code, 400)
        with self.assertRaises(HTTPError) as error:
            self.post("/api/v1/subscriptions/search", {"siteKey": "a", "query": "x" * 70000})
        self.assertEqual(error.exception.code, 413)


if __name__ == "__main__":
    unittest.main()
