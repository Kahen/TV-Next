#!/usr/bin/env python3
"""Owned, synthetic account/WS/persistence checks for the isolated NAS CI stack."""
import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("TV_NEXT_TEST_WEB_URL", "http://127.0.0.1:3000")


def request(path, value=None, token=None, expected=200):
    headers = {"Origin": BASE}
    if value is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(BASE + "/api/v1/home/" + path,
                                 data=None if value is None else json.dumps(value).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            assert response.status == expected, (path, response.status)
            assert response.headers.get("X-Request-Id"), "Missing correlation ID"
            return json.load(response)
    except urllib.error.HTTPError as error:
        assert error.code == expected, (path, error.code, expected)
        return None


def healthy():
    for _ in range(90):
        try:
            with urllib.request.urlopen(BASE + "/api/v1/health", timeout=3) as response:
                if response.status == 200:
                    return
        except OSError:
            pass
        time.sleep(2)
    raise AssertionError("NAS Web/API did not become healthy")


def upgrade(ticket, expected=101):
    url = urllib.parse.urlsplit(BASE)
    peer = socket.create_connection((url.hostname, url.port or 80), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    peer.sendall((f"GET /api/v1/home/remote/socket?ticket={ticket} HTTP/1.1\r\nHost: {url.netloc}\r\n"
                  f"Origin: {BASE}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                  f"Sec-WebSocket-Key: {key}\r\n\r\n").encode())
    header = bytearray()
    while not header.endswith(b"\r\n\r\n"):
        value = peer.recv(1)
        if not value:
            raise AssertionError("Truncated upgrade")
        header.extend(value)
        assert len(header) < 16384
    assert int(header.split(b" ", 2)[1]) == expected, "WebSocket upgrade status"
    if expected == 101:
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        assert accept in header, "Invalid WS acceptance"
        return peer
    peer.close()
    return None


def read_exact(peer, length):
    output = bytearray()
    while len(output) < length:
        value = peer.recv(length - len(output))
        if not value:
            raise AssertionError("Remote frame truncated")
        output.extend(value)
    return bytes(output)


def receive(peer):
    first, second = read_exact(peer, 2)
    assert first == 0x81 and not second & 0x80
    size = second & 127
    if size == 126:
        size = struct.unpack("!H", read_exact(peer, 2))[0]
    elif size == 127:
        size = struct.unpack("!Q", read_exact(peer, 8))[0]
    assert size <= 16384
    return json.loads(read_exact(peer, size))


def send(peer, payload):
    body = json.dumps(payload).encode()
    mask = os.urandom(4)
    header = bytes([0x81, 0x80 | len(body)]) if len(body) < 126 else bytes([0x81, 0x80 | 126]) + struct.pack("!H", len(body))
    peer.sendall(header + mask + bytes(value ^ mask[index % 4] for index, value in enumerate(body)))


def wait_remote_receiver(token, device_id, attempts=40, delay=0.1):
    """A 101 upgrade can arrive before the server has registered the receiver."""
    for _ in range(attempts):
        devices = request("remote/devices", token=token)
        if any(device.get("id") == device_id and device.get("online") is True for device in devices):
            return
        time.sleep(delay)
    raise AssertionError("WebSocket receiver never became online")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--restart-api", action="store_true", help="Restart only the isolated CI NAS API to prove persistence")
    args = parser.parse_args()
    healthy()
    first = request("auth/register", {"username": "nas-fixture-a", "password": "fixture-only-long-password", "deviceName": "Controller"})
    second = request("auth/register", {"username": "nas-fixture-b", "password": "fixture-only-long-password", "deviceName": "Other user"})
    a, b = first["token"], second["token"]
    request("library", expected=401)
    snapshot = {"version": 1, "channels": [{"name": "Owned fixture", "url": "https://example.org/never-fetched.mp4", "group": "Test"}],
                "favorites": [], "recent": [], "positions": {"https://example.org/never-fetched.mp4": 45}}
    saved = request("library", {"expectedRevision": 0, "library": snapshot}, a)
    assert saved["revision"] == 1
    request("library", {"expectedRevision": 0, "library": snapshot}, a, 409)
    assert request("library", token=b)["library"]["channels"] == []
    request("devices/" + second["device"]["id"] + "/revoke", {}, a, 404)
    code = request("pairings", {}, a)["code"]
    paired = request("pairings/claim", {"code": code, "deviceName": "Tablet"})
    request("pairings/claim", {"code": code, "deviceName": "Replay"}, expected=401)
    assert request("library", token=paired["token"])["revision"] == 1
    request("devices/" + paired["device"]["id"] + "/revoke", {}, a)
    request("library", token=paired["token"], expected=401)

    ticket = request("remote/ticket", {}, a)["ticket"]
    with upgrade(ticket) as peer:
        wait_remote_receiver(a, first["device"]["id"])
        command = request("remote/commands", {"targetDeviceId": first["device"]["id"], "type": "PAUSE"}, a)
        packet = receive(peer)
        assert packet["id"] == command["id"] and packet["type"] == "PAUSE"
        send(peer, {"type": "ACK", "id": packet["id"], "success": True})
        for _ in range(30):
            status = request("remote/commands/" + packet["id"], token=a)
            if status["state"] == "acknowledged":
                break
            time.sleep(0.1)
        assert status["state"] == "acknowledged"
        request("remote/commands/" + packet["id"], token=b, expected=404)
        upgrade(ticket, expected=401)

    if args.restart_api:
        subprocess.run(["docker", "compose", "-f", "compose.nas.yaml", "restart", "api"], check=True, capture_output=True)
        healthy()
        assert request("library", token=a)["library"]["positions"]["https://example.org/never-fetched.mp4"] == 45
    internal = os.environ.get("TV_NEXT_TEST_INTERNAL_API_URL")
    if internal:
        with urllib.request.urlopen(internal + "/actuator/prometheus", timeout=5) as response:
            metrics = response.read()
            assert b"jvm_" in metrics and b"fixture-only-long-password" not in metrics
    with urllib.request.urlopen(BASE + "/actuator/prometheus", timeout=5) as response:
        assert b"jvm_memory_" not in response.read(), "Metrics leaked through Web proxy"
    print("PASS: PostgreSQL accounts, scoped CAS, pairing/revocation, nginx WS ticket/ACK and API restart persistence")


if __name__ == "__main__":
    main()
