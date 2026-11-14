"""Ensure localhost WebDAV response framing survives request entities and EOF."""
import http.client
import threading
import unittest
from http.server import ThreadingHTTPServer
from webdav_fixture_server import Handler, XML


class WebDAVFixtureTests(unittest.TestCase):
    def test_caption_get_formats_rejections_and_stream_framing(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for name, status, expected in [
                ('Owned.srt', 200, b'Owned captions'),
                ('Unicode.vtt', 200, b'WEBVTT'),
                ('Utf16.srt', 200, 'Owned captions'.encode('utf-16-le')),
                ('Legacy.srt', 200, '中文字幕'.encode('gb18030')),
                ('Styled.ass', 200, b'[Events]'),
                ('Redirect.srt', 302, b''), ('Redirect-local.srt', 302, b''),
                ('Unauthorized.srt', 401, b''), ('Partial.srt', 206, b''),
                ('Large.srt', 200, b'x' * 1_048_577), ('Streamed.srt', 200, b'x' * 1_048_577),
            ]:
                with self.subTest(name=name):
                    client = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
                    client.request('GET', '/captions/' + name)
                    response = client.getresponse()
                    self.assertEqual(response.status, status)
                    body = response.read()
                    self.assertIn(expected, body)
                    if name == 'Streamed.srt':
                        self.assertEqual(response.getheader('Transfer-Encoding'), 'chunked')
                        self.assertEqual(len(body), 1_048_577)
                    if status == 302:
                        self.assertTrue(response.getheader('Location'))
                    client.close()
            client = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
            client.request('GET', '/captions/Owned.srt', headers={'Authorization': 'Basic unexpected'})
            self.assertEqual(client.getresponse().status, 403)
            client.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_propfind_entities_are_drained_before_chunked_or_eof_response(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for path, expected in [('/dav/', XML),
                                   ('/dav/no-length/', XML.replace(b'/dav/', b'/dav/no-length/')),
                                   ('/dav/large-streamed/', b'x' * 1_048_577)]:
                with self.subTest(path=path):
                    client = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
                    client.request('PROPFIND', path, body=b'<propfind/>' * 30, headers={'Depth': '1'})
                    response = client.getresponse()
                    self.assertEqual(response.status, 207)
                    self.assertEqual(response.read(), expected)
                    client.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == '__main__':
    unittest.main()
