import Foundation
import XCTest
@testable import TVNext

final class NativeSSDPResolverTests: XCTestCase {
    private let target = NativeSSDPResponse.mediaRenderer
    private var location: URL { URL(string: "http://192.168.1.20:1400/device.xml")! }

    private func candidate(_ location: URL? = nil, usn: String? = nil,
                           target: String? = nil) -> NativeSSDPResponse.Candidate {
        let selected = target ?? self.target
        return .init(location: location ?? self.location, serviceType: selected,
                     uniqueServiceName: usn ?? "uuid:owned-123::" + selected)
    }

    private func details(_ udn: String? = "uuid:Owned-123",
                         control: String = "http://192.168.1.20:1400/upnp/control")
        -> NativeDLNADescription.Details {
        .init(controlURL: URL(string: control)!, friendlyName: "Owned Renderer",
              modelName: nil, deviceUDN: udn)
    }

    func testOwnedCandidatePromotesOnlyAfterMatchingDescription() async throws {
        let expected = details()
        var requests: [URL] = []
        let result = try await NativeSSDPResolver.resolve(candidate(), fetch: { url in
            requests.append(url)
            return expected
        })
        XCTAssertEqual(requests, [location])
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.deviceUDN, "uuid:Owned-123")
    }

    func testUnsafeCandidateRejectedBeforeNetworkIO() async {
        let cases = [
            candidate(URL(string: "http://127.0.0.1:1400/device.xml")!),
            candidate(URL(string: "http://8.8.8.8:1400/device.xml")!),
            candidate(URL(string: "http://192.168.1.20:1400/device%2Fxml")!),
            candidate(target: "ssdp:all"),
            candidate(usn: "uuid:owned-123::" + NativeSSDPResponse.avTransport),
            candidate(usn: "uuid:bad identity::" + target),
            candidate(usn: "uuid:" + String(repeating: "a", count: 124) + "::" + target)
        ]
        for (index, item) in cases.enumerated() {
            var fetched = false
            do {
                _ = try await NativeSSDPResolver.resolve(item, fetch: { _ in
                    fetched = true
                    return details()
                })
                XCTFail("Unsafe candidate accepted: \(index)")
            } catch {
                XCTAssertEqual(error as? NativeDLNAError, .invalidDescription, "Case \(index)")
            }
            XCTAssertFalse(fetched, "Unsafe candidate fetched: \(index)")
        }
    }

    func testMissingMismatchedUDNAndForeignControlRejected() async {
        let cases = [
            details(nil), details("uuid:other"),
            details(control: "http://192.168.1.21:1400/upnp/control"),
            details(control: "http://192.168.1.20:1401/upnp/control")
        ]
        for (index, item) in cases.enumerated() {
            do {
                _ = try await NativeSSDPResolver.resolve(candidate(), fetch: { _ in item })
                XCTFail("Forged description accepted: \(index)")
            } catch {
                XCTAssertEqual(error as? NativeDLNAError, .invalidDescription, "Case \(index)")
            }
        }
    }

    func testPreCancelledResolutionDoesNotFetch() async {
        let item = candidate()
        let expected = details()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeSSDPResolver.resolve(item, fetch: { _ in
                XCTFail("Cancelled operation attempted network fetch")
                return expected
            })
        }
        do { _ = try await task.value; XCTFail("Cancelled operation succeeded") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected cancellation error: \(error)") }
    }
}
