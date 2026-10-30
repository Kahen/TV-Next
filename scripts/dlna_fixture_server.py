"""Owned loopback-only DLNA AVTransport SOAP fixture; no external streams."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from time import sleep
from xml.etree import ElementTree as ET

HOST, PORT = '127.0.0.1', 8768
SOAP = 'http://schemas.xmlsoap.org/soap/envelope/'
SERVICE = 'urn:schemas-upnp-org:service:AVTransport:1'


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        return self.reply(200, b'ok') if self.path == '/health' else self.reply(404, b'not found')

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
            assert action in ('SetAVTransportURI', 'Play', 'Pause', 'Stop', 'GetTransportInfo')
            root = ET.fromstring(payload)
            body = root.find(f'{{{SOAP}}}Body')
            assert body is not None
            node = body.find(f'{{{SERVICE}}}{action}')
            assert node is not None and node.findtext('InstanceID') == '0'
            if action == 'SetAVTransportURI':
                assert node.findtext('CurrentURI') == 'https://media.example/owned.mp4?a=1&b=2'
                assert node.find('CurrentURIMetaData') is not None
            if action == 'Play':
                assert node.findtext('Speed') == '1'
            if action == 'GetTransportInfo':
                assert len(node) == 1
        except (AssertionError, ValueError, KeyError, IndexError, ET.ParseError):
            return self.reply(400, b'invalid SOAP')
        if action == 'SetAVTransportURI':
            self.server.transport_state = 'STOPPED'
        elif action == 'Play':
            self.server.transport_state = 'PLAYING'
        elif action == 'Pause':
            self.server.transport_state = 'PAUSED_PLAYBACK'
        elif action == 'Stop':
            self.server.transport_state = 'STOPPED'
        state = getattr(self.server, 'transport_state', 'STOPPED')
        response_content = (f'<CurrentTransportState>{state}</CurrentTransportState>'
                            '<CurrentTransportStatus>OK</CurrentTransportStatus>'
                            '<CurrentSpeed>1</CurrentSpeed>') if action == 'GetTransportInfo' else ''
        result = (f'<s:Envelope xmlns:s="{SOAP}"><s:Body>'
                  f'<u:{action}Response xmlns:u="{SERVICE}">{response_content}</u:{action}Response>'
                  f'</s:Body></s:Envelope>').encode()
        return self.reply(200, result, {'Content-Type': 'text/xml; charset=utf-8'})


if __name__ == '__main__':
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
