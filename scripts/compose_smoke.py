#!/usr/bin/env python3
"""In-container-deployment integration smoke, using only Python's standard library.

Never fetches third-party media, external plugins or XMLTV URLs.
"""
import json
import sys
import time
import urllib.error
import urllib.request

API = "http://127.0.0.1:8080"
WEB = "http://127.0.0.1:3000"


def request(url, value=None):
    body = json.dumps(value).encode("utf-8") if value is not None else None
    headers = {"Content-Type": "application/json"} if body is not None else {}
    method = "POST" if body is not None else "GET"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, (url, response.status)
        return response.read()


def wait_for_health():
    last = None
    for _ in range(90):
        try:
            health = json.loads(request(API + "/api/v1/health"))
            if health.get("status") == "ok":
                print("API ready", flush=True)
                return
        except (urllib.error.URLError, TimeoutError, ValueError, AssertionError) as error:
            last = error
        time.sleep(2)
    raise RuntimeError(f"API did not become healthy: {last}")


def main():
    wait_for_health()
    index = request(WEB + "/")
    assert b"TV-Next" in index, "Web page is not served"
    proxy_health = json.loads(request(WEB + "/api/v1/health"))
    assert proxy_health.get("status") == "ok", "nginx proxy failed"

    m3u = {
        "content": '#EXTM3U\n#EXTINF:-1 tvg-id="fixture" group-title="News",Fixture TV\n'
                   'https://example.org/fixture.m3u8\n'
    }
    playlist = json.loads(request(WEB + "/api/v1/playlists/parse", m3u))
    assert playlist["channels"][0]["tvgId"] == "fixture", playlist

    xmltv = (
        '<tv><channel id="fixture"><display-name>Fixture TV</display-name></channel>'
        '<programme channel="fixture" start="20261020120000 +0000" '
        'stop="20261020130000 +0000"><title>Fixture News</title></programme></tv>'
    )
    guide = json.loads(request(WEB + "/api/v1/epg/guide", {
        "xml": xmltv,
        "channels": [{"id": "fixture", "name": "Fixture TV"}],
        "at": "2026-10-20T12:30:00Z",
        "hours": 12
    }))
    assert guide["matchedChannels"] == 1, guide
    assert guide["channels"][0]["current"]["title"] == "Fixture News", guide

    media_result = json.dumps({
        "class": [{"type_id": "movie", "type_name": "Movie"}],
        "list": [{"vod_id": "fixture-movie", "vod_name": "Sample Movie"}]
    })
    movie = json.loads(request(WEB + "/api/v1/media/home", {"content": media_result}))
    assert movie["items"][0]["id"] == "fixture-movie", movie

    print("SUCCESS: nginx Web + API proxy + M3U + XMLTV + MediaProvider", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Compose smoke FAILED: {error}", file=sys.stderr)
        raise
