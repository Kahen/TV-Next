"""Deterministic bundled-fixture runtime, not a full FongMi/Android Spider."""
import json
import os
import socket
import sys
import time


class WorkerError(Exception):
    pass


METHODS = {"home", "category", "search", "detail", "player"}
TEST_METHODS = {"__probe_network", "__probe_write", "__probe_policy", "__sleep"}
with open("/worker/catalog.json", encoding="utf-8") as fixture_file:
    FIXTURE = json.load(fixture_file)


def limited_text(value, limit=200):
    return value.strip() if isinstance(value, str) and len(value) <= limit else ""


def execute(req):
    if (not isinstance(req, dict) or req.get("version") != 1 or
            not isinstance(req.get("method"), str) or
            not isinstance(req.get("args"), dict)):
        raise WorkerError("invalid-request")
    method = req["method"]
    args = req["args"]
    if method in TEST_METHODS:
        if os.environ.get("TVNEXT_TEST_HOOKS") != "1":
            raise WorkerError("unsupported-method")
        if method == "__probe_network":
            try:
                with socket.create_connection(("1.1.1.1", 53), timeout=0.9):
                    return {"network": "unexpected-success"}
            except OSError:
                return {"network": "blocked"}
        if method == "__probe_write":
            try:
                with open("/worker/probe", "w", encoding="utf-8") as output:
                    output.write("x")
                return {"readonly": False}
            except OSError:
                return {"readonly": True}
        if method == "__probe_policy":
            def read(name):
                try:
                    with open("/sys/fs/cgroup/" + name, encoding="ascii") as f:
                        return f.read().strip()
                except OSError:
                    return None

            return {
                "uid": os.getuid(),
                "hostSecretVisible": "TVNEXT_HOST_SECRET_TEST" in os.environ,
                "memoryMax": read("memory.max"),
                "pidsMax": read("pids.max"),
                "cpuMax": read("cpu.max")
            }
        if method == "__sleep":
            time.sleep(30)
            return {"slept": True}
    if method not in METHODS:
        raise WorkerError("unsupported-method")
    categories, items = FIXTURE["categories"], FIXTURE["items"]

    def summary(item):
        return {key: value for key, value in item.items() if key != "episodes"}

    if method == "home":
        return {"categories": categories, "items": [summary(i) for i in items]}
    if method == "category":
        category_id = limited_text(args.get("categoryId"))
        if not category_id:
            raise WorkerError("missing-category")
        return {"categories": categories, "items": [
            summary(i) for i in items if i["categoryId"] == category_id
        ]}
    if method == "search":
        query = limited_text(args.get("query"), 120).lower()
        if not query:
            raise WorkerError("missing-query")
        return {"items": [summary(i) for i in items if query in i["name"].lower()]}
    item = next((i for i in items if i["id"] == limited_text(args.get("vodId"))), None)
    if item is None:
        raise WorkerError("unknown-item")
    if method == "detail":
        return item
    index = args.get("episodeIndex")
    if type(index) is not int or not 0 <= index < len(item["episodes"]):
        raise WorkerError("unknown-episode")
    return item["episodes"][index]


def main():
    try:
        raw = sys.stdin.buffer.read(16_385)
        if len(raw) > 16_384:
            raise WorkerError("request-too-large")
        request = json.loads(raw)
        response = {"version": 1, "status": "ok", "runtime": "python",
                    "data": execute(request)}
        print(json.dumps(response, separators=(",", ":")))
    except (json.JSONDecodeError, UnicodeDecodeError):
        print(json.dumps({"version": 1, "status": "error", "code": "invalid-input"}))
        sys.exit(2)
    except WorkerError as error:
        print(json.dumps({"version": 1, "status": "error", "code": str(error)}))
        sys.exit(2)


if __name__ == "__main__":
    main()
