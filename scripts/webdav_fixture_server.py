#!/usr/bin/env python3
"""Owned, localhost-only RFC 4918 fixture for native WebDAV CI."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

XML = b'''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/Owned.mp4</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/Folder/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>https://foreign.example/evil.mp4</d:href></d:response>
</d:multistatus>'''

class Handler(BaseHTTPRequestHandler):
    def do_PROPFIND(self):
        if self.path == '/dav/':
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
            # Explicit HTTP/1.1 chunked framing exercises an unknown-length
            # transfer without relying on platform-specific EOF behavior.
            # Send 16 exact 64-KiB chunks plus one overflow byte.
            self.protocol_version = 'HTTP/1.1'
            self.send_response(207)
            self.send_header('Content-Type', 'application/xml')
            self.send_header('Transfer-Encoding', 'chunked')
            self.send_header('Connection', 'close')
            self.close_connection = True
            self.end_headers()
            try:
                for chunk in ([b'x' * 65_536] * 16 + [b'x']):
                    self.wfile.write(f'{len(chunk):X}\r\n'.encode('ascii'))
                    self.wfile.write(chunk + b'\r\n')
                    self.wfile.flush()
                self.wfile.write(b'0\r\n\r\n')
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
