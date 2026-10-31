import Foundation
import XCTest
@testable import TVNext

final class NativeSSDPResponseTests: XCTestCase {
    private func packet(st: String = NativeSSDPResponse.mediaRenderer,
                        location: String = "http://192.168.1.20:1400/device.xml",
                        extra: String = "") -> Data {
        Data("HTTP/1.1 200 OK\r\nST: \(st)\r\nUSN: uuid:owned-123::\(st)\r\nLOCATION: \(location)\r\n\(extra)\r\n".utf8)
    }

    func testAcceptsBoundedPrivateSenderMatchedRendererAndAVTransport() throws {
        for st in [NativeSSDPResponse.mediaRenderer, NativeSSDPResponse.avTransport] {
            let candidate = try NativeSSDPResponse.parse(packet(st: st), senderIPv4: "192.168.1.20")
            XCTAssertEqual(candidate.serviceType, st)
            XCTAssertEqual(candidate.location.absoluteString, "http://192.168.1.20:1400/device.xml")
            XCTAssertEqual(candidate.uniqueServiceName, "uuid:owned-123::\(st)")
        }
    }

    func testRejectsForgedOriginDuplicatesAndUnsupportedTargets() {
        let cases = [
            packet(location: "http://8.8.8.8:1400/device.xml"),
            packet(location: "http://192.168.1.21:1400/device.xml"),
            packet(location: "http://192.168.1.20:1400/device.xml?token=secret"),
            packet(extra: "LOCATION: http://192.168.1.20:1400/other.xml\r\n"),
            packet(extra: "ST: \(NativeSSDPResponse.mediaRenderer)\r\n"),
            packet(st: "ssdp:all"),
            Data("HTTP/1.1 200 OK\nLOCATION: http://192.168.1.20:1400/device.xml\n\n".utf8),
            packet() + Data("trailing body".utf8),
            packet() + Data("\rX-Forged: value".utf8),
            Data(repeating: 65, count: NativeSSDPResponse.maxDatagramBytes + 1)
        ]
        for (index, data) in cases.enumerated() {
            XCTAssertThrowsError(try NativeSSDPResponse.parse(data, senderIPv4: "192.168.1.20"), "Case \(index)")
        }
        XCTAssertThrowsError(try NativeSSDPResponse.parse(packet(), senderIPv4: "8.8.8.8"))
    }
}
