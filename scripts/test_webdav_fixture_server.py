"""Ensure localhost WebDAV response framing survives request entities and EOF."""
import http.client
import threading
import unittest
from http.server import ThreadingHTTPServer
from webdav_fixture_server import Handler, XML


class WebDAVFixtureTests(unittest.TestCase):
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
