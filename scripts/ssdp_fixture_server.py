#!/usr/bin/env python3
"""Owned loopback UDP SSDP M-SEARCH capture fixture, not a real LAN renderer."""
import json
import pathlib
import socket
import sys

PORT = 19090
OUTPUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/tvnext-ssdp-fixture.json")
TARGETS = {
    "urn:schemas-upnp-org:device:MediaRenderer:1",
    "urn:schemas-upnp-org:service:AVTransport:1",
}


def main():
    seen = []
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", PORT))
        sock.settimeout(8)
        print("ready", flush=True)
        while len(seen) < 2:
            data, sender = sock.recvfrom(8192)
            packet = data.decode("ascii")
            assert packet.startswith("M-SEARCH * HTTP/1.1\r\n")
            assert packet.endswith("\r\n\r\n")
            assert "HOST: 239.255.255.250:1900\r\n" in packet
            assert 'MAN: "ssdp:discover"\r\n' in packet
            assert "MX: 2\r\n" in packet
            st = next((line[4:] for line in packet.split("\r\n") if line.startswith("ST: ")), None)
            assert st in TARGETS and st not in seen, st
            seen.append(st)
            # Matching LOCATION and source are loopback; production parser
            # deliberately rejects them as LAN discovery candidates.
            reply = (f"HTTP/1.1 200 OK\r\nST: {st}\r\n"
                     f"USN: uuid:owned-fixture::{st}\r\n"
                     "LOCATION: http://127.0.0.1:8768/device.xml\r\n\r\n").encode("ascii")
            sock.sendto(reply, sender)
            sock.sendto(b"X" * 4097, sender)
    OUTPUT.write_text(json.dumps({"targets": seen, "requests": len(seen)}))


if __name__ == "__main__":
    main()
