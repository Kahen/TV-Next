#!/usr/bin/env python3
"""Owned localhost-only FongMi search fixture for production SwiftUI XCUI.
No external streams, plugins, credentials or network requests.
"""
import json
import threading
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_lock = threading.Lock()
_counts = Counter()
_queries = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def respond(self, code, payload):
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == "/health":
            return self.respond(200, {"ok": True})
        if self.path == "/fixture/reset":
            with _lock:
                _counts.clear()
                _queries.clear()
            return self.respond(200, {"ok": True})
        if self.path == "/fixture/state":
            with _lock:
                snapshot = {"counts": dict(_counts), "queries": list(_queries)}
            return self.respond(200, snapshot)
        return self.respond(404, {"error": "unknown fixture route"})

    def do_POST(self):
        if self.path not in ("/api/v1/subscriptions/load", "/api/v1/subscriptions/search"):
            return self.respond(404, {"error": "unknown fixture route"})
        try:
            length = int(self.headers.get("Content-Length", "-1"))
            if not 0 <= length <= 65536:
                return self.respond(413, {"error": "fixture request too large"})
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError("object required")
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
            return self.respond(400, {"error": "invalid fixture request"})
        if self.path.endswith("/load"):
            return self.respond(200, {
                "content": "owned fixture", "url": "", "depots": [],
                "liveCount": 0, "warnings": [],
                "sites": [
                    # Deliberately put a hidden duplicate B first. A raw
                    # first(where: key) lookup would mislabel B's results.
                    {"key": "b", "name": "Hidden Spoof", "type": 0,
                     "searchable": True, "hidden": True, "support": ""},
                    {"key": "a", "name": "Mirror", "type": 0,
                     "searchable": True, "hidden": False, "support": ""},
                    {"key": "b", "name": "Mirror", "type": 0,
                     "searchable": True, "hidden": False, "support": ""}
                ]
            })
        key = body.get("siteKey")
        keyword = body.get("query")
        if key not in ("a", "b") or not isinstance(keyword, str):
            return self.respond(400, {"error": "invalid fixture site"})
        with _lock:
            _counts[key] += 1
            count = _counts[key]
            _queries.append({"siteKey": key, "query": keyword})
        # An explicit zero-hit search succeeds on both providers; it must
        # not be misreported as a failure or show a retry action.
        if keyword == "no-results":
            return self.respond(200, {
                "categories": [], "filters": {}, "total": 0,
                "page": 1, "hasMore": False, "items": []
            })
        # An oversized terminal page is valid fixture data: the iOS client
        # must retain only 40 entries and explicitly disclose the clipping,
        # even though the provider advertises no further pages.
        if keyword == "oversized-page":
            items = ([{"id": f"a-{index}", "name": f"Fixture {index:02d}",
                       "remarks": None, "folder": False, "action": None}
                      for index in range(41)] if key == "a" else [])
            return self.respond(200, {
                "categories": [], "filters": {}, "total": len(items),
                "page": 1, "hasMore": False, "items": items
            })
        # B's first page is clipped, page 2 fails, then a failed-only retry
        # returns an exact 40-item terminal page. A is never retried.
        if keyword == "retry-warning":
            page = body.get("page", 1)
            if key == "a":
                return self.respond(200, {
                    "categories": [], "filters": {}, "total": 1,
                    "page": 1, "hasMore": False,
                    "items": [{"id": "a-stable", "name": "Healthy",
                               "remarks": None, "folder": False, "action": None}]
                })
            if key == "b" and count == 1 and page == 1:
                items = [{"id": f"old-{i}", "name": f"Old {i}",
                          "remarks": None, "folder": False, "action": None}
                         for i in range(41)]
                return self.respond(200, {
                    "categories": [], "filters": {}, "total": 41,
                    "page": 1, "hasMore": True, "items": items
                })
            if key == "b" and count == 2 and page == 2:
                return self.respond(503, {"error": "synthetic page-2 failure"})
            if key == "b" and count == 3 and page == 1:
                items = [{"id": f"new-{i}", "name": f"New {i}",
                          "remarks": None, "folder": False, "action": None}
                         for i in range(40)]
                return self.respond(200, {
                    "categories": [], "filters": {}, "total": 40,
                    "page": 1, "hasMore": False, "items": items
                })
            return self.respond(409, {"error": "unexpected retry page or provider"})
        if key == "b" and count == 1:
            return self.respond(503, {"error": "synthetic transient failure"})
        # Fail closed if SwiftUI re-queries a healthy site or retries using
        # an edited draft instead of the original submitted keyword.
        if (key == "a" and count > 1) or (key == "b" and count > 1 and keyword != "original"):
            return self.respond(409, {"error": "unexpected retry scope or keyword"})
        return self.respond(200, {
            "categories": [], "filters": {}, "total": 1,
            "page": 1, "hasMore": False,
            "items": [{"id": key + "-id", "name": ("A result" if key == "a" else "B result"),
                       "remarks": None, "folder": False, "action": None}]
        })

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8769), Handler).serve_forever()
