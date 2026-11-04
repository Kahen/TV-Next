import Foundation

@main
struct SSDPDiscoverySmoke {
    static func main() throws {
        for target in [NativeSSDPResponse.mediaRenderer, NativeSSDPResponse.avTransport] {
            guard let packet = NativeSSDPDiscovery.request(for: target),
                  let text = String(data: packet, encoding: .ascii) else { fatalError("Missing request") }
            precondition(text == "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(target)\r\n\r\n")
            precondition(packet.count < 512)
        }
        precondition(NativeSSDPDiscovery.request(for: "ssdp:all") == nil)
        precondition(NativeSSDPDiscovery.request(for: "urn:malicious\r\nX-Forged: yes") == nil)
        let first = NativeSSDPResponse.Candidate(
            location: URL(string: "http://192.168.1.20:1400/device.xml")!,
            serviceType: NativeSSDPResponse.mediaRenderer,
            uniqueServiceName: "uuid:owned::" + NativeSSDPResponse.mediaRenderer)
        let duplicate = NativeSSDPResponse.Candidate(
            location: first.location, serviceType: NativeSSDPResponse.avTransport,
            uniqueServiceName: "uuid:owned::" + NativeSSDPResponse.avTransport)
        let second = NativeSSDPResponse.Candidate(
            location: URL(string: "http://192.168.1.21:1400/device.xml")!,
            serviceType: NativeSSDPResponse.mediaRenderer,
            uniqueServiceName: "uuid:other::" + NativeSSDPResponse.mediaRenderer)
        precondition(NativeSSDPDiscovery.deduplicated([first, duplicate, second]) == [first, second])
        precondition(NativeSSDPDiscovery.deduplicated(Array(repeating: first, count: 100)) == [first])
        let many = (0..<64).map { index in
            NativeSSDPResponse.Candidate(
                location: URL(string: "http://192.168.1.20:1400/device-\(index).xml")!,
                serviceType: NativeSSDPResponse.mediaRenderer,
                uniqueServiceName: "uuid:owned-\(index)::" + NativeSSDPResponse.mediaRenderer)
        }
        precondition(NativeSSDPDiscovery.deduplicated(many).count == NativeSSDPDiscovery.maxCandidates)
        #if DEBUG
        // An owned localhost UDP server captures the two M-SEARCH packets and
        // sends forged loopback responses. They must never become LAN candidates.
        let discovered = try NativeSSDPDiscovery.scanLoopbackFixture(port: 19090)
        precondition(discovered.isEmpty)
        #endif
        print("SSDP bounded M-SEARCH transport, strict targets, dedupe, candidate cap and loopback rejection passed")
    }
}
