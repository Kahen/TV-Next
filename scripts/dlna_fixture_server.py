"""Owned loopback-only DLNA AVTransport SOAP fixture; no external streams."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from time import sleep
import re
from xml.etree import ElementTree as ET

HOST, PORT = '127.0.0.1', 8768
SOAP = 'http://schemas.xmlsoap.org/soap/envelope/'
SERVICE = 'urn:schemas-upnp-org:service:AVTransport:1'


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == '/health':
            return self.reply(200, b'ok')
        if self.path == '/device-redirect':
            return self.reply(302, b'', {'Location': 'http://8.8.8.8/device.xml'})
        if self.path == '/device-oversize':
            return self.reply(200, b'X' * 32769)
        if self.path in ('/device.xml', '/device-foreign.xml', '/device-duplicate.xml',
                         '/device-missing.xml', '/device-doctype.xml',
                         '/device-name-duplicate.xml', '/device-name-unsafe.xml',
                         '/device-model-missing.xml', '/device-model-duplicate.xml',
                         '/device-model-nested.xml', '/device-model-foreign.xml',
                         '/device-model-unsafe.xml', '/device-model-oversize.xml',
                         '/device-multiple-root.xml'):
            service = ('<service><serviceType>' + SERVICE + '</serviceType>'
                       '<controlURL>/upnp/control/AVTransport1</controlURL></service>')
            if self.path == '/device-foreign.xml':
                service = service.replace('/upnp/control/AVTransport1',
                                          'http://8.8.8.8:8768/upnp/control')
            if self.path == '/device-duplicate.xml':
                service += service
            if self.path == '/device-missing.xml':
                service = ''
            name = '<friendlyName>TV-Next Test Renderer</friendlyName>'
            if self.path == '/device-name-duplicate.xml':
                name += '<friendlyName>Forged Renderer</friendlyName>'
            if self.path == '/device-name-unsafe.xml':
                name = '<friendlyName>Forged\u202eName</friendlyName>'
            udn = '<UDN>uuid:tvnext-fixture</UDN>'
            model = '<modelName>TV-Next Test Model 1</modelName>'
            if self.path == '/device-model-missing.xml':
                model = ''
            if self.path == '/device-model-duplicate.xml':
                model += '<modelName>Forged Model</modelName>'
            if self.path == '/device-model-nested.xml':
                model = '<modelName>TV-Next<fake/> Model</modelName>'
            if self.path == '/device-model-foreign.xml':
                model = '<x:modelName xmlns:x="urn:foreign">Forged</x:modelName>'
            if self.path == '/device-model-unsafe.xml':
                model = '<modelName>Forged\u202eModel</modelName>'
            if self.path == '/device-model-oversize.xml':
                model = '<modelName>' + 'é' * 81 + '</modelName>'
            xml = ('<root xmlns="urn:schemas-upnp-org:device-1-0">'
                   '<URLBase>http://8.8.8.8:80/</URLBase>'
                   '<device>' + name + model + udn + '<serviceList>' + service + '</serviceList></device></root>')
            if self.path == '/device-multiple-root.xml':
                xml = ('<root xmlns="urn:schemas-upnp-org:device-1-0">'
                       '<device><friendlyName>First</friendlyName></device>'
                       '<device>' + model + '<serviceList>' + service + '</serviceList></device></root>')
            if self.path == '/device-doctype.xml':
                xml = '<!DOCTYPE root [<!ENTITY secret SYSTEM "file:///etc/passwd">]>' + xml
            return self.reply(200, xml.encode(), {'Content-Type': 'text/xml; charset=utf-8'})
        return self.reply(404, b'not found')

    def reply(self, status, body, headers=None):
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path == '/redirect':
            return self.reply(302, b'', {'Location': 'http://127.0.0.1:8768/upnp/control/AVTransport1'})
        if self.path == '/oversize':
            return self.reply(200, b'X' * 32769)
        if self.path == '/slow':
            self.send_response(200)
            self.send_header('Content-Length', '1024')
            self.end_headers()
            self.wfile.write(b'x')
            self.wfile.flush()
            sleep(12)
            return
        if self.path == '/fault':
            return self.reply(500, b'<s:Fault>owned failure</s:Fault>')
        if self.path != '/upnp/control/AVTransport1':
            return self.reply(404, b'not found')
        try:
            size = int(self.headers.get('Content-Length', '0'))
            assert 0 < size <= 8192
            payload = self.rfile.read(size)
            action = self.headers['SOAPACTION'].strip('"').split('#', 1)[1]
            assert action in ('SetAVTransportURI', 'Play', 'Pause', 'Stop', 'GetTransportInfo', 'GetPositionInfo', 'Seek')
            root = ET.fromstring(payload)
            body = root.find(f'{{{SOAP}}}Body')
            assert body is not None
            node = body.find(f'{{{SERVICE}}}{action}')
            assert node is not None and node.findtext('InstanceID') == '0'
            if action == 'SetAVTransportURI':
                assert node.findtext('CurrentURI') == 'https://media.example/owned.mp4?a=1&b=2'
                metadata_node = node.find('CurrentURIMetaData')
                assert metadata_node is not None
                metadata = metadata_node.text or ''
                if metadata:
                    didl_ns = '{urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/}'
                    dc_ns = '{http://purl.org/dc/elements/1.1/}'
                    upnp_ns = '{urn:schemas-upnp-org:metadata-1-0/upnp/}'
                    didl = ET.fromstring(metadata)
                    assert didl.tag == didl_ns + 'DIDL-Lite' and len(didl) == 1
                    item = didl.find(didl_ns + 'item')
                    assert item is not None and item.attrib == {'id': '0', 'parentID': '-1', 'restricted': '1'}
                    assert item.findtext(dc_ns + 'title') in ('Owned Video', 'Owned & <Demo>')
                    assert item.findtext(upnp_ns + 'class') == 'object.item.videoItem'
                    res = item.find(didl_ns + 'res')
                    assert res is not None and res.attrib == {'protocolInfo': 'http-get:*:video/*:*'}
                    assert res.text == 'https://media.example/owned.mp4?a=1&b=2'
            if action == 'Play':
                assert node.findtext('Speed') == '1'
            if action in ('GetTransportInfo', 'GetPositionInfo'):
                assert len(node) == 1
            if action == 'Seek':
                assert [child.tag for child in node] == ['InstanceID', 'Unit', 'Target']
                assert node.findtext('Unit') == 'REL_TIME'
                target = node.findtext('Target')
                assert target is not None and re.fullmatch(r'[0-9]{2}:[0-9]{2}:[0-9]{2}', target)
                hours, minutes, seconds = map(int, target.split(':'))
                assert minutes < 60 and seconds < 60
                requested_seconds = hours * 3600 + minutes * 60 + seconds
                assert 0 <= requested_seconds <= 120
                assert getattr(self.server, 'transport_state', 'STOPPED') in ('PLAYING', 'PAUSED_PLAYBACK')
        except (AssertionError, ValueError, KeyError, IndexError, ET.ParseError):
            return self.reply(400, b'invalid SOAP')
        if action == 'SetAVTransportURI':
            self.server.transport_state = 'STOPPED'
            self.server.position_seconds = 0
        elif action == 'Play':
            self.server.transport_state = 'PLAYING'
            self.server.position_seconds = 42
        elif action == 'Seek':
            self.server.position_seconds = requested_seconds
        elif action == 'Pause':
            self.server.transport_state = 'PAUSED_PLAYBACK'
        elif action == 'Stop':
            self.server.transport_state = 'STOPPED'
            self.server.position_seconds = 0
        state = getattr(self.server, 'transport_state', 'STOPPED')
        response_content = (f'<CurrentTransportState>{state}</CurrentTransportState>'
                            '<CurrentTransportStatus>OK</CurrentTransportStatus>'
                            '<CurrentSpeed>1</CurrentSpeed>') if action == 'GetTransportInfo' else (
            f'<TrackDuration>00:02:00</TrackDuration>'
            f'<RelTime>{getattr(self.server, "position_seconds", 0)//3600:02d}:'
            f'{getattr(self.server, "position_seconds", 0)//60%60:02d}:'
            f'{getattr(self.server, "position_seconds", 0)%60:02d}</RelTime>'
        ) if action == 'GetPositionInfo' else ''
        result = (f'<s:Envelope xmlns:s="{SOAP}"><s:Body>'
                  f'<u:{action}Response xmlns:u="{SERVICE}">{response_content}</u:{action}Response>'
                  f'</s:Body></s:Envelope>').encode()
        return self.reply(200, result, {'Content-Type': 'text/xml; charset=utf-8'})


if __name__ == '__main__':
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
