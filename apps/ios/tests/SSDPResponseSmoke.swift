import Foundation

@main struct SSDPResponseSmoke {
    static func main() throws {
        func packet(_ st: String = NativeSSDPResponse.mediaRenderer,
                    _ location: String = "http://192.168.1.20:1400/device.xml",
                    _ usn: String? = nil) -> Data {
            let identifier = usn ?? "uuid:owned-device-123::\(st)"
            return Data("HTTP/1.1 200 OK\r\nST: \(st)\r\nUSN: \(identifier)\r\nLOCATION: \(location)\r\nCACHE-CONTROL: max-age=1800\r\n\r\n".utf8)
        }
        let valid = try NativeSSDPResponse.parse(packet(), senderIPv4: "192.168.1.20")
        precondition(valid.location.absoluteString == "http://192.168.1.20:1400/device.xml")
        precondition(valid.serviceType == NativeSSDPResponse.mediaRenderer)
        let transport = try NativeSSDPResponse.parse(packet(NativeSSDPResponse.avTransport), senderIPv4: "192.168.1.20")
        precondition(transport.serviceType == NativeSSDPResponse.avTransport)
        // UPnP 1.1 requires empty EXT and dotted BOOTID/CONFIGID headers.
        let standard = Data("HTTP/1.1 200 OK\r\nST: \(NativeSSDPResponse.mediaRenderer)\r\nUSN: uuid:owned-device-123::\(NativeSSDPResponse.mediaRenderer)\r\nLOCATION: http://192.168.1.20:1400/device.xml\r\nEXT:\r\nBOOTID.UPNP.ORG: 1\r\nCONFIGID.UPNP.ORG: 2\r\nSEARCHPORT.UPNP.ORG: 1900\r\n\r\n".utf8)
        let compliant = try NativeSSDPResponse.parse(standard, senderIPv4: "192.168.1.20")
        precondition(compliant == valid)
        let bad = [
            packet("ssdp:all"), packet(NativeSSDPResponse.mediaRenderer, "http://8.8.8.8:1400/device.xml"),
            packet(NativeSSDPResponse.mediaRenderer, "http://192.168.1.21:1400/device.xml"),
            packet(NativeSSDPResponse.mediaRenderer, "http://192.168.1.20:1400/../admin"),
            packet(NativeSSDPResponse.mediaRenderer, "http://192.168.1.20:1400/device.xml?x=1"),
            packet(NativeSSDPResponse.mediaRenderer, "http://192.168.1.20:1400/device.xml", "uuid:wrong::ssdp:all"),
            Data("HTTP/1.1 200 OK\nST: \(NativeSSDPResponse.mediaRenderer)\n\n".utf8),
            packet() + Data("BODY".utf8),
            packet() + Data([0]),
            packet() + Data([9]),
            packet() + Data("\rX-Forged: value".utf8),
            packet().dropLast(2) + Data("\r\nLOCATION: http://192.168.1.20:1400/evil\r\n\r\n".utf8),
            Data(repeating: 65, count: NativeSSDPResponse.maxDatagramBytes + 1),
            Data("HTTP/1.1 200 OK\r\nST: \(NativeSSDPResponse.mediaRenderer)\r\n USN: uuid:x\r\n\r\n".utf8)
        ]
        for (index, data) in bad.enumerated() {
            do {
                _ = try NativeSSDPResponse.parse(Data(data), senderIPv4: "192.168.1.20")
                fatalError("Accepted unsafe SSDP datagram #\(index)")
            } catch is NativeSSDPResponse.ValidationError { }
        }
        do { _ = try NativeSSDPResponse.parse(packet(), senderIPv4: "8.8.8.8"); fatalError("Accepted public sender") }
        catch NativeSSDPResponse.ValidationError.unsafeLocation { }
        // Even a matching loopback sender and LOCATION cannot advertise a LAN renderer.
        do {
            _ = try NativeSSDPResponse.parse(
                packet(NativeSSDPResponse.mediaRenderer, "http://127.0.0.1:1400/device.xml"),
                senderIPv4: "127.0.0.1"
            )
            fatalError("Accepted a loopback SSDP discovery candidate")
        } catch NativeSSDPResponse.ValidationError.unsafeLocation { }
        print("SSDP bounded M-SEARCH response parser positive/negative smoke passed")
    }
}
