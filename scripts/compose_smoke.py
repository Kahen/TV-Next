#!/usr/bin/env python3
"""In-container-deployment integration smoke, using only Python's standard library.

Never fetches third-party media, external plugins or XMLTV URLs.
"""
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request

API = "http://127.0.0.1:8080"
WEB = "http://127.0.0.1:3000"


def request(url, value=None, origin=None):
    body = json.dumps(value).encode("utf-8") if value is not None else None
    headers = {"Content-Type": "application/json"} if body is not None else {}
    if origin:
        headers["Origin"] = origin
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
            index = request(WEB + "/")
            reverse_health = json.loads(request(WEB + "/api/v1/health"))
            if health.get("status") == "ok" and b"TV-Next" in index and reverse_health.get("status") == "ok":
                print("API, Web and nginx proxy ready", flush=True)
                return
        except (OSError, ValueError, AssertionError) as error:
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
    playlist = json.loads(request(WEB + "/api/v1/playlists/parse", m3u, WEB))
    assert playlist["channels"][0]["tvgId"] == "fixture", playlist

    config = json.dumps({
        "spider": "https://example.org/never-loaded.jar",
        "sites": [{"key": "fixture-site", "name": "Fixture", "type": 3}],
        "lives": [{"name": "Fixture IPTV", "groups": [{"name": "News", "channel": [
            {"name": "Fixture TV", "urls": ["https://example.org/fixture.m3u8"]}
        ]}]}]
    })
    inspection = json.loads(request(WEB + "/api/v1/configs/inspect", {"content": config}))
    assert inspection["spiderDeclared"] is True and inspection["sites"][0]["key"] == "fixture-site", inspection
    catalog = json.loads(request(WEB + "/api/v1/catalog/preview", {"content": config}))
    assert catalog["sites"][0]["key"] == "fixture-site", catalog
    assert catalog["directPlayableChannelCount"] == 1, catalog

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

    # Prove nginx accepts a realistic XMLTV body larger than its old default 1 MiB cap.
    large_xmltv = xmltv.replace("<tv>", "<tv><!--" + ("a" * 1_100_000) + "-->", 1)
    large_guide = json.loads(request(WEB + "/api/v1/epg/guide", {
        "xml": large_xmltv,
        "channels": [{"id": "fixture", "name": "Fixture TV"}],
        "at": "2026-10-20T12:30:00Z",
        "hours": 12
    }))
    assert large_guide["matchedChannels"] == 1, "Reverse proxy rejected bounded XMLTV document"

    # Prove hostile external entities never get expanded by the API.
    try:
        request(WEB + "/api/v1/epg/guide", {
            "xml": '<!DOCTYPE tv [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><tv/>',
            "channels": [{"name": "Fixture TV"}]
        })
        raise AssertionError("DOCTYPE unexpectedly accepted")
    except urllib.error.HTTPError as error:
        assert error.code == 400, error.code

    # Shared golden Result: the same authorized synthetic data is parsed by
    # Swift offline and Kotlin MockMvc, and now exercised through nginx + real API.
    media_result = (Path(__file__).resolve().parent.parent
                    / "fixtures/p2-fongmi-result.json").read_text(encoding="utf-8")

    def media(endpoint, **fields):
        return json.loads(request(
            WEB + "/api/v1/media/" + endpoint,
            {"content": media_result, **fields}
        ))

    movie = media("home")
    assert movie["total"] == 3 and len(movie["categories"]) == 2, movie
    assert movie["items"][0]["id"] == "film-1", movie
    category = media("category", categoryId="movie")
    assert category["total"] == 2, category
    matches = media("search", query="FIXTURE")
    assert matches["total"] == 2, matches
    detail = media("detail", vodId="film-1")
    assert len(detail["lines"]) == 2, detail
    assert detail["lines"][1]["episodes"][0]["playable"] is False, detail
    playable = media("play", vodId="film-1", lineIndex=0, episodeIndex=1)
    assert playable["url"] == "https://example.org/movie2.m3u8", playable
    for video_id, line_index, episode_index in [
        ("film-1", 1, 0), ("unsafe", 0, 0)
    ]:
        try:
            media("play", vodId=video_id,
                  lineIndex=line_index, episodeIndex=episode_index)
            raise AssertionError("Unsupported episode unexpectedly allowed")
        except urllib.error.HTTPError as error:
            assert error.code == 422, (video_id, error.code)

    subscription = json.loads(request(WEB + "/api/v1/subscriptions/load", {
        "url": "https://example.org/a/config.json", "content": json.dumps({
            "spider":"./spider.jar", "sites":[{"key":"pan","type":4,"api":"https://example.org/api","ext":{"token":"own-fixture"}}],
            "urls":[{"name":"Next","url":"../next.json"}]})
    }))
    assert subscription["sites"][0]["type"] == 4
    assert subscription["sites"][0]["jar"] == "https://example.org/a/spider.jar"
    assert subscription["depots"][0]["url"] == "https://example.org/next.json"
    for endpoint, payload, status in [
        ("/resources/text", {"url":"http://169.254.169.254/latest/meta-data/"}, 502),
        ("/cloud/list", {"server":"https://example.org", "path":"/../secret"}, 400),
        ("/subscriptions/detail", {"content":config,"siteKey":"fixture-site","vodId":"1"}, 422)
    ]:
        try:
            request(WEB + "/api/v1" + endpoint, payload)
            raise AssertionError("Forbidden request unexpectedly accepted: " + endpoint)
        except urllib.error.HTTPError as error:
            assert error.code == status, (endpoint,error.code)
    print("SUCCESS: nginx + API + M3U + config + catalog + XMLTV + MediaProvider + subscriptions + network guards", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Compose smoke FAILED: {error}", file=sys.stderr)
        raise
