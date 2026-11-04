import Foundation
import XCTest
@testable import TVNext

final class NativeSSDPDiscoveryTests: XCTestCase {
    func testOnlyFixedBoundedMSearchRequestsAreBuilt() throws {
        for target in [NativeSSDPResponse.mediaRenderer, NativeSSDPResponse.avTransport] {
            let request = try XCTUnwrap(NativeSSDPDiscovery.request(for: target))
            XCTAssertEqual(String(data: request, encoding: .ascii),
                           "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(target)\r\n\r\n")
            XCTAssertLessThan(request.count, 512)
        }
        XCTAssertNil(NativeSSDPDiscovery.request(for: "ssdp:all"))
        XCTAssertNil(NativeSSDPDiscovery.request(for: "x\r\nLOCATION: http://8.8.8.8/"))
    }

    func testCandidateDeduplicationAndHardCap() throws {
        let target = NativeSSDPResponse.mediaRenderer
        let items = (0..<64).map { index in
            NativeSSDPResponse.Candidate(
                location: URL(string: "http://192.168.1.20:1400/device-\(index).xml")!,
                serviceType: target, uniqueServiceName: "uuid:owned-\(index)::\(target)")
        }
        XCTAssertEqual(NativeSSDPDiscovery.deduplicated(items + items).count, 32)
        XCTAssertEqual(NativeSSDPDiscovery.deduplicated([items[0], items[0], items[1]]),
                       [items[0], items[1]])
        XCTAssertTrue(NativeSSDPDiscovery.deduplicated([]).isEmpty)
    }
}
