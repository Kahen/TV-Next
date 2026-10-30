import Foundation
import XCTest
@testable import TVNext

final class NativeDLNATests: XCTestCase {
    func testRendererPrivateLiteralValidation() throws {
        for address in ["http://10.0.0.2:1400/upnp/control", "http://172.16.1.2:49152/AVTransport", "http://172.31.255.254:80/upnp", "http://192.168.1.20:1400/MediaRenderer/AVTransport/Control", "http://127.0.0.1:8768/upnp/control/AVTransport1"] {
            XCTAssertNoThrow(try NativeDLNA.rendererURL(address))
        }
        for address in ["http://172.32.0.1:1400/upnp", "http://169.254.0.1:1400/upnp", "http://8.8.8.8:1400/upnp", "http://localhost:8768/upnp", "https://192.168.1.20:1400/upnp", "http://192.168.1.20/upnp", "http://192.168.1.20:0/upnp", "http://user:pass@192.168.1.20:1400/upnp", "http://192.168.1.20:1400/upnp?token=x", "http://192.168.1.20:1400/upnp/%2e%2e/private"] {
            XCTAssertThrowsError(try NativeDLNA.rendererURL(address), "Rejected \(address)")
        }
    }

    func testSOAPEscapingAndMediaRestrictions() throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        let set = try NativeDLNA.request(.setURI, endpoint: endpoint, media: media)
        XCTAssertEqual(set.httpMethod, "POST")
        XCTAssertEqual(set.value(forHTTPHeaderField: "SOAPACTION"), "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"")
        XCTAssertTrue(String(decoding: set.httpBody!, as: UTF8.self).contains("a=1&amp;b=2"))
        XCTAssertThrowsError(try NativeDLNA.request(.setURI, endpoint: endpoint))
        XCTAssertThrowsError(try NativeDLNA.mediaURL("file:///private/media.mp4"))
        XCTAssertThrowsError(try NativeDLNA.mediaURL("https://user:pass@media.example/video.mp4"))
        XCTAssertThrowsError(try NativeDLNA.mediaURL("https://media.example/video.mp4", hasHeaders: true))
        XCTAssertThrowsError(try NativeDLNA.mediaURL("https://media.example/video.mp4", replay: true))
    }

    func testNamespacedResponseAndMalformedResponseRejection() throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let ok = Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:PlayResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/></s:Body></s:Envelope>".utf8)
        XCTAssertNoThrow(try NativeDLNA.validate(ok, response: response, action: .play))
        for body in ["<html>PlayResponse</html>", "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:PauseResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/></s:Body></s:Envelope>", "<!DOCTYPE foo><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:PlayResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/></s:Body></s:Envelope>"] {
            XCTAssertThrowsError(try NativeDLNA.validate(Data(body.utf8), response: response, action: .play))
        }
        XCTAssertThrowsError(try NativeDLNA.validate(Data(repeating: 65, count: 32769), response: response, action: .play))
    }

    func testOwnedLoopbackTransportAndFailureModes() async throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        try await NativeDLNA.cast(endpoint: endpoint, media: media)
        try await NativeDLNA.send(.pause, endpoint: endpoint)
        try await NativeDLNA.send(.stop, endpoint: endpoint)
        for (path, status) in [("redirect", 302), ("fault", 500)] {
            let url = try NativeDLNA.rendererURL("http://127.0.0.1:8768/\(path)")
            do { try await NativeDLNA.send(.play, endpoint: url); XCTFail("Accepted \(path)") }
            catch NativeDLNAError.httpStatus(let actual) { XCTAssertEqual(actual, status) }
        }
        let oversized = try NativeDLNA.rendererURL("http://127.0.0.1:8768/oversize")
        do { try await NativeDLNA.send(.play, endpoint: oversized); XCTFail("Accepted oversized body") }
        catch NativeDLNAError.responseTooLarge { }
    }

    func testPreCancelledRequestThrowsInsteadOfCrashingSession() async throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let pending = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await NativeDLNA.send(.play, endpoint: endpoint)
        }
        do { try await pending.value; XCTFail("Pre-cancelled request unexpectedly succeeded") }
        catch is CancellationError { }
    }
}
