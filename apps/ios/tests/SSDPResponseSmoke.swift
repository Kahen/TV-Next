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
        print("SSDP bounded M-SEARCH response parser positive/negative smoke passed")
    }
}
