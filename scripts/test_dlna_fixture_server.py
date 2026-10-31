"""Owned loopback SOAP fixture positive/negative HTTP tests."""
import http.client
from html import escape
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

    def post(self, path, action='Play', media=None, target=None, metadata=''):
        arguments = '<InstanceID>0</InstanceID>'
        if action == 'SetAVTransportURI':
            arguments += f'<CurrentURI>{media}</CurrentURI><CurrentURIMetaData>{escape(metadata)}</CurrentURIMetaData>'
        if action == 'Play':
            arguments += '<Speed>1</Speed>'
        if action == 'Seek':
            arguments += f'<Unit>REL_TIME</Unit><Target>{target}</Target>'
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

    def test_owned_device_descriptions_and_rejections(self):
        for path, expected_status, expected_fragment in [
            ('/device.xml', 200, b'/upnp/control/AVTransport1'),
            ('/device-foreign.xml', 200, b'http://8.8.8.8:8768'),
            ('/device-duplicate.xml', 200, b'<service><serviceType>'),
            ('/device-missing.xml', 200, b'<serviceList></serviceList>'),
            ('/device-doctype.xml', 200, b'<!DOCTYPE'),
            ('/device-redirect', 302, b''),
            ('/device-oversize', 200, b'X' * 32769),
        ]:
            connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
            try:
                connection.request('GET', path)
                response = connection.getresponse()
                self.assertEqual(response.status, expected_status)
                body = response.read()
                self.assertIn(expected_fragment, body)
                if path == '/device-oversize':
                    self.assertEqual(len(body), 32769)
                if path == '/device-redirect':
                    self.assertEqual(response.getheader('Location'), 'http://8.8.8.8/device.xml')
            finally:
                connection.close()

    def test_valid_actions(self):
        for action in ('SetAVTransportURI', 'Play', 'Pause', 'Stop'):
            status, body = self.post('/upnp/control/AVTransport1', action,
                                     'https://media.example/owned.mp4?a=1&amp;b=2')
            self.assertEqual(status, 200)
            self.assertIn((action + 'Response').encode(), body)

    def test_opt_in_didl_lite_metadata(self):
        didl = ('<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
                'xmlns:dc="http://purl.org/dc/elements/1.1/" '
                'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
                '<item id="0" parentID="-1" restricted="1">'
                '<dc:title>Owned &amp; &lt;Demo&gt;</dc:title>'
                '<upnp:class>object.item.videoItem</upnp:class>'
                '<res protocolInfo="http-get:*:video/*:*">'
                'https://media.example/owned.mp4?a=1&amp;b=2</res>'
                '</item></DIDL-Lite>')
        media = 'https://media.example/owned.mp4?a=1&amp;b=2'
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'SetAVTransportURI',
                                   media, metadata=didl)[0], 200)
        for invalid in ('<bad/>', didl.replace('Owned &amp; &lt;Demo&gt;', 'Forged'),
                        didl.replace('http-get:*:video/*:*', 'http-get:*:application/x-executable:*')):
            self.assertEqual(self.post('/upnp/control/AVTransport1', 'SetAVTransportURI',
                                       media, metadata=invalid)[0], 400)

    def test_transport_state_tracks_commands(self):
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'SetAVTransportURI',
                                   'https://media.example/owned.mp4?a=1&amp;b=2')[0], 200)
        status, body = self.post('/upnp/control/AVTransport1', 'GetTransportInfo')
        self.assertEqual(status, 200)
        self.assertIn(b'<CurrentTransportState>STOPPED</CurrentTransportState>', body)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Play')[0], 200)
        self.assertIn(b'<CurrentTransportState>PLAYING</CurrentTransportState>',
                      self.post('/upnp/control/AVTransport1', 'GetTransportInfo')[1])
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Pause')[0], 200)
        self.assertIn(b'<CurrentTransportState>PAUSED_PLAYBACK</CurrentTransportState>',
                      self.post('/upnp/control/AVTransport1', 'GetTransportInfo')[1])
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Stop')[0], 200)
        self.assertIn(b'<CurrentTransportState>STOPPED</CurrentTransportState>',
                      self.post('/upnp/control/AVTransport1', 'GetTransportInfo')[1])

    def test_position_snapshot_tracks_owned_fixture(self):
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'SetAVTransportURI',
                                   'https://media.example/owned.mp4?a=1&amp;b=2')[0], 200)
        self.assertIn(b'<RelTime>00:00:00</RelTime>',
                      self.post('/upnp/control/AVTransport1', 'GetPositionInfo')[1])
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Play')[0], 200)
        status, body = self.post('/upnp/control/AVTransport1', 'GetPositionInfo')
        self.assertEqual(status, 200)
        self.assertIn(b'<RelTime>00:00:42</RelTime>', body)
        self.assertIn(b'<TrackDuration>00:02:00</TrackDuration>', body)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Stop')[0], 200)
        self.assertIn(b'<RelTime>00:00:00</RelTime>',
                      self.post('/upnp/control/AVTransport1', 'GetPositionInfo')[1])

    def test_seek_tracks_position_and_rejects_invalid_or_stopped_requests(self):
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'SetAVTransportURI',
                                   'https://media.example/owned.mp4?a=1&amp;b=2')[0], 200)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Seek', target='00:00:57')[0], 400)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Play')[0], 200)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Seek', target='00:00:57')[0], 200)
        self.assertIn(b'<RelTime>00:00:57</RelTime>',
                      self.post('/upnp/control/AVTransport1', 'GetPositionInfo')[1])
        for target in ('00:02:01', '00:60:00', '-1', '00:00:57extra', '00:00:57:00', ''):
            self.assertEqual(self.post('/upnp/control/AVTransport1', 'Seek', target=target)[0], 400)
        self.assertIn(b'<RelTime>00:00:57</RelTime>',
                      self.post('/upnp/control/AVTransport1', 'GetPositionInfo')[1])
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Pause')[0], 200)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Seek', target='00:00:42')[0], 200)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Stop')[0], 200)
        self.assertEqual(self.post('/upnp/control/AVTransport1', 'Seek', target='00:00:15')[0], 400)

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
