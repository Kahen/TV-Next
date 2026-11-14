#!/usr/bin/env python3
"""Owned, localhost-only RFC 4918 fixture for native WebDAV CI."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from time import sleep

XML = b'''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/Owned.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>2048</d:getcontentlength><d:getlastmodified>Mon, 01 Jan 2024 12:34:56 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/Folder/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>https://foreign.example/evil.mp4</d:href></d:response>
</d:multistatus>'''

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.removeprefix('/captions/')
        if not self.path.startswith('/captions/'):
            self.send_error(404)
            return
        # Anonymous loopback requests must never inherit draft credentials.
        if self.headers.get('Authorization') or self.headers.get('Cookie'):
            self.send_error(403)
            return
        srt = '1\n00:00:01,000 --> 00:00:03,000\nOwned captions\n'
        bodies = {
            'Owned.srt': srt.encode(),
            'Unicode.vtt': b'WEBVTT\n\n00:01.000 --> 00:03.000\nOwned captions\n',
            'Utf16.srt': srt.encode('utf-16'),
            'Legacy.srt': srt.replace('Owned captions', '中文字幕').encode('gb18030'),
            'Styled.ass': b'[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Owned captions\n',
            'Invalid.srt': b'<html>not a subtitle</html>',
            'Large.srt': b'x' * 1_048_577,
            'Slow.srt': srt.encode(),
        }
        if name in ('Redirect.srt', 'Redirect-local.srt'):
            self.send_response(302)
            self.send_header('Location', 'https://foreign.example/captions/Owned.srt' if name == 'Redirect.srt' else '/captions/Owned.srt')
            self.send_header('Content-Length', '0')
            self.end_headers()
        elif name in ('Unauthorized.srt', 'Partial.srt'):
            self.send_response(401 if name == 'Unauthorized.srt' else 206)
            self.send_header('Content-Length', '0')
            self.end_headers()
        elif name == 'Streamed.srt':
            self.protocol_version = 'HTTP/1.1'
            self.send_response(200)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            try:
                for chunk in ([b'x' * 8192] * 128 + [b'x']):
                    self.wfile.write(f'{len(chunk):X}\r\n'.encode() + chunk + b'\r\n')
                    self.wfile.flush()
                    sleep(0.004)
                self.wfile.write(b'0\r\n\r\n')
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
        elif name in bodies:
            body = bodies[name]
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            if name == 'Slow.srt':
                sleep(3)
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            self.send_error(404)

    def do_PROPFIND(self):
        # Consume the entity before replying/closing. Closing a TCP connection
        # with unread request bytes can send RST; CFNetwork then loses the last
        # chunk and reports -1005 instead of exercising the client's byte cap.
        try:
            size = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            self.send_error(400)
            return
        if not 0 <= size <= 4096 or self.headers.get('Transfer-Encoding'):
            self.send_error(400)
            return
        if len(self.rfile.read(size)) != size:
            self.send_error(400)
            return
        if self.path == '/captions/':
            names = ['Owned.srt', 'Invalid.srt', 'Slow.srt']
            records = ''.join(f'<d:response><d:href>/captions/{name}</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>' for name in names)
            body = ('<?xml version="1.0" encoding="utf-8"?><d:multistatus xmlns:d="DAV:">' + records + '</d:multistatus>').encode()
            self.send_response(207)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == '/dav/':
            if self.headers.get('Depth') != '1':
                self.send_error(400)
                return
            self.send_response(207)
            self.send_header('Content-Type', 'application/xml; charset=utf-8')
            self.send_header('Content-Length', str(len(XML)))
            self.end_headers()
            self.wfile.write(XML)
        elif self.path == '/dav/Folder/':
            body = b'''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/Folder/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</d:multistatus>'''
            self.send_response(207)
            self.send_header('Content-Type', 'application/xml; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == '/dav/redirect/':
            self.send_response(302)
            self.send_header('Location', 'https://foreign.example/dav/')
            self.end_headers()
        elif self.path == '/dav/redirect-local/':
            # Redirects must be denied even when they stay on the same origin.
            self.send_response(302)
            self.send_header('Location', '/dav/')
            self.end_headers()
        elif self.path == '/dav/no-length/':
            # Explicit EOF is required for a body with no Content-Length.
            # Do not rely on platform-specific keep-alive/HTTP version defaults.
            self.send_response(207)
            self.send_header('Content-Type', 'application/xml')
            self.send_header('Connection', 'close')
            self.close_connection = True
            self.end_headers()
            self.wfile.write(XML.replace(b'/dav/', b'/dav/no-length/'))
        elif self.path == '/dav/large-declared/':
            # The client must reject this declared size before reading the body.
            self.send_response(207)
            self.send_header('Content-Type', 'application/xml')
            self.send_header('Content-Length', str(1_048_577))
            self.end_headers()
            try:
                self.wfile.write(b'x' * 1_048_577)
            except (BrokenPipeError, ConnectionResetError):
                pass
        elif self.path == '/dav/large-streamed/':
            # A valid keep-alive HTTP/1.1 chunked body with no Content-Length.
            # Pace small chunks so CFNetwork delivers incremental data callbacks
            # before the final chunk (an immediate close was reported as -1005
            # instead of reaching the 1 MiB application-level size guard).
            # Exactly 128 * 8192 + 1 decoded bytes cross the bound.
            self.protocol_version = 'HTTP/1.1'
            self.send_response(207)
            self.send_header('Content-Type', 'application/xml')
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            try:
                for chunk in ([b'x' * 8_192] * 128 + [b'x']):
                    self.wfile.write(f'{len(chunk):X}\r\n'.encode('ascii'))
                    self.wfile.write(chunk + b'\r\n')
                    self.wfile.flush()
                    sleep(0.004)
                self.wfile.write(b'0\r\n\r\n')
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass  # Expected when the bounded client cancels the transfer.
        elif self.path in ('/dav/unauthorized/', '/dav/forbidden/', '/dav/ok-not-multistatus/', '/dav/empty-multistatus/'):
            status = {
                '/dav/unauthorized/': 401,
                '/dav/forbidden/': 403,
                '/dav/ok-not-multistatus/': 200,
                '/dav/empty-multistatus/': 207,
            }[self.path]
            self.send_response(status)
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            self.send_error(404)

    def log_message(self, *_args):
        pass

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8767), Handler).serve_forever()
