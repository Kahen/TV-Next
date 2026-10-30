"""Owned loopback SOAP fixture positive/negative HTTP tests."""
import http.client
import threading
import unittest
from http.server import ThreadingHTTPServer
from dlna_fixture_server import Handler, SERVICE, SOAP


class DLNAFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def post(self, path, action='Play', media=None):
        arguments = '<InstanceID>0</InstanceID>'
        if action == 'SetAVTransportURI':
            arguments += f'<CurrentURI>{media}</CurrentURI><CurrentURIMetaData></CurrentURIMetaData>'
        if action == 'Play':
            arguments += '<Speed>1</Speed>'
        body = (f'<s:Envelope xmlns:s="{SOAP}"><s:Body>'
                f'<u:{action} xmlns:u="{SERVICE}">{arguments}</u:{action}>'
                f'</s:Body></s:Envelope>')
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        try:
            connection.request('POST', path, body=body.encode(), headers={'SOAPACTION': f'"{SERVICE}#{action}"'})
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_valid_actions(self):
        for action in ('SetAVTransportURI', 'Play', 'Pause', 'Stop'):
            status, body = self.post('/upnp/control/AVTransport1', action,
                                     'https://media.example/owned.mp4?a=1&amp;b=2')
            self.assertEqual(status, 200)
            self.assertIn((action + 'Response').encode(), body)

    def test_rejects_invalid_action_and_uri(self):
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Delete')[0], 400)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'SetAVTransportURI', 'file:///private/a')[0], 400)
        self.assertEqual(self.post('/unknown')[0], 404)

    def test_redirect_fault_and_oversize(self):
        self.assertEqual(self.post('/redirect')[0], 302)
        self.assertEqual(self.post('/fault')[0], 500)
        status, body = self.post('/oversize')
        self.assertEqual(status, 200)
        self.assertEqual(len(body), 32769)


if __name__ == '__main__':
    unittest.main()
