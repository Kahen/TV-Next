#!/usr/bin/env python3
"""Local synthetic H.264/MP4/HLS fixture for actual browser playback; no external streams."""
import http.server
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.parse


with tempfile.TemporaryDirectory(prefix="tv-next-browser-media-") as temporary:
    directory = Path(temporary)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                    "testsrc=size=160x90:rate=5", "-t", "90", "-c:v", "libx264", "-threads", "1",
                    "-pix_fmt", "yuv420p", "-profile:v", "baseline", "-g", "10", "-movflags", "+faststart",
                    str(directory / "fixture.mp4")], check=True, timeout=60)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(directory / "fixture.mp4"),
                    "-c", "copy", "-hls_time", "6", "-hls_list_size", "0", "-hls_segment_filename",
                    str(directory / "segment-%03d.ts"), str(directory / "fixture.m3u8")], check=True, timeout=30)

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_OPTIONS(self):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET,HEAD,OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Range")
            self.end_headers()

        def do_HEAD(self):
            self.serve(False)

        def do_GET(self):
            self.serve(True)

        def serve(self, body):
            name = urllib.parse.urlsplit(self.path).path.lstrip("/")
            if not re.fullmatch(r"fixture\.(mp4|m3u8)|segment-[0-9]{3}\.ts", name):
                self.send_error(404)
                return
            path = directory / name
            if not path.is_file():
                self.send_error(404)
                return
            size = path.stat().st_size
            start, end, status = 0, size - 1, 200
            if self.headers.get("Range"):
                match = re.fullmatch(r"bytes=([0-9]+)-([0-9]*)", self.headers["Range"])
                if not match:
                    self.send_error(416)
                    return
                start = int(match[1])
                end = min(int(match[2]) if match[2] else end, end)
                if start > end:
                    self.send_error(416)
                    return
                status = 206
            self.send_response(status)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Expose-Headers", "Content-Length,Content-Range,Accept-Ranges")
            self.send_header("Content-Type", "application/vnd.apple.mpegurl" if name.endswith("m3u8") else "video/mp2t" if name.endswith("ts") else "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(end - start + 1))
            if status == 206:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()
            if body:
                with path.open("rb") as stream:
                    stream.seek(start)
                    try:
                        self.wfile.write(stream.read(end - start + 1))
                    except (BrokenPipeError, ConnectionResetError):
                        pass

    print("Synthetic browser MP4/HLS fixture ready at 127.0.0.1:8765", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
