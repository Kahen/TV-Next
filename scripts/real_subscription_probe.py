#!/usr/bin/env python3
"""Explicit operator-invoked subscription smoke; never executes downloaded code.

Pass an authorized URL. Reports counts and fingerprints, never the config,
extensions, headers, source names, tokens or media URLs. Not part of normal CI.
"""
import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from collections import Counter


def probe(api, subscription_url):
    request = urllib.request.Request(
        api.rstrip("/") + "/api/v1/subscriptions/load",
        data=json.dumps({"url": subscription_url}, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        raw = response.read(3_145_729)
        if len(raw) > 3_145_728:
            raise ValueError("oversized-response")
        document = json.loads(raw)
    sites = document.get("sites")
    if not isinstance(sites, list) or not sites:
        raise ValueError("subscription-has-no-sites")
    return {
        "status": "subscription-loaded",
        "sites": len(sites),
        "types": dict(Counter(str(site["type"]) for site in sites)),
        "support": dict(Counter(site["support"] for site in sites)),
        "normalizedConfigSha256": hashlib.sha256(document["content"].encode("utf-8")).hexdigest(),
        "spiderExecuted": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api", default="http://127.0.0.1:8080")
    parser.add_argument("--subscription-url", required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(probe(args.api, args.subscription_url), sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        # Never dump a remote error body or a URL containing secret query params.
        print(json.dumps({"status": "failed", "error": type(error).__name__}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
