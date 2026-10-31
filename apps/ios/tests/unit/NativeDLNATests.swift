import Foundation
import XCTest
@testable import TVNext

final class NativeDLNATests: XCTestCase {
    func testAbsoluteSeekStrictTimeAndDuration() throws {
        XCTAssertEqual(try NativeDLNASeek.parseAbsolute("00:01:30"), 90)
        XCTAssertEqual(try NativeDLNASeek.parseAbsolute("99:59:59"), NativeDLNASeek.maxSeconds)
        XCTAssertEqual(try NativeDLNASeek.parseAbsolute("00:00:00"), 0)
        for invalid in ["1:01:30", "00:60:00", "00:00:60", "100:00:00",
                        "00:01:3a", "00:01:30 ", "00:01:30\n", "００:０１:３０"] {
            XCTAssertThrowsError(try NativeDLNASeek.parseAbsolute(invalid))
        }
        let finite = NativeDLNAPosition(seconds: 42, durationSeconds: 120)
        XCTAssertEqual(try NativeDLNASeek.absoluteTarget(position: finite, requestedSeconds: 0), 0)
        XCTAssertEqual(try NativeDLNASeek.absoluteTarget(position: finite, requestedSeconds: 120), 120)
        for invalid in [-1, 121, Int.max] {
            XCTAssertThrowsError(try NativeDLNASeek.absoluteTarget(position: finite, requestedSeconds: invalid))
        }
        XCTAssertThrowsError(try NativeDLNASeek.absoluteTarget(
            position: NativeDLNAPosition(seconds: 42, durationSeconds: nil), requestedSeconds: 30))
    }

    func testOwnedLoopbackAbsoluteSeekAndStoppedRejection() async throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        try await NativeDLNA.cast(endpoint: endpoint, media: media)
        let requested = try await NativeDLNA.seekAbsolute(endpoint: endpoint, targetText: "00:01:30")
        XCTAssertEqual(requested, 90)
        let reported = try await NativeDLNA.queryPosition(endpoint: endpoint)
        XCTAssertEqual(reported.seconds, 90)
        do {
            _ = try await NativeDLNA.seekAbsolute(endpoint: endpoint, targetText: "00:02:01")
            XCTFail("Accepted absolute seek beyond duration")
        } catch NativeDLNAError.invalidSeek { }
        try await NativeDLNA.send(.stop, endpoint: endpoint)
        do {
            _ = try await NativeDLNA.seekAbsolute(endpoint: endpoint, targetText: "00:00:30")
            XCTFail("Accepted absolute seek on stopped renderer")
        } catch NativeDLNAError.unsupportedSeek { }
    }

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

    func testOptInDIDLLiteMetadataAndInvalidTitles() throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        let empty = try NativeDLNA.request(.setURI, endpoint: endpoint, media: media)
        XCTAssertTrue(String(decoding: empty.httpBody!, as: UTF8.self).contains("<CurrentURIMetaData></CurrentURIMetaData>"))
        let didl = try NativeDLNA.didlMetadata(media: media, title: "Owned & <Demo>")
        XCTAssertTrue(didl.contains("<dc:title>Owned &amp; &lt;Demo&gt;</dc:title>"))
        XCTAssertTrue(didl.contains("http-get:*:video/*:*"))
        XCTAssertTrue(didl.contains("owned.mp4?a=1&amp;b=2"))
        let request = try NativeDLNA.request(.setURI, endpoint: endpoint, media: media, metadataTitle: "Owned & <Demo>")
        let soap = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(soap.contains("&lt;DIDL-Lite"))
        XCTAssertTrue(soap.contains("Owned &amp;amp; &amp;lt;Demo&amp;gt;"))
        // Both the embedded DIDL document and its outer SOAP envelope must
        // remain well-formed after escaping untrusted titles and URL queries.
        XCTAssertTrue(XMLParser(data: Data(didl.utf8)).parse())
        XCTAssertTrue(XMLParser(data: request.httpBody!).parse())
        for unsafeMedia in ["file:///private/owned.mp4", "https://user:pass@media.example/owned.mp4"] {
            XCTAssertThrowsError(try NativeDLNA.request(
                .setURI, endpoint: endpoint, media: URL(string: unsafeMedia)!))
            XCTAssertThrowsError(try NativeDLNA.request(
                .setURI, endpoint: endpoint, media: URL(string: unsafeMedia)!,
                metadataTitle: "Owned"))
        }
        let xmlNoncharacters: [[UInt8]] = [[0xEF, 0xBF, 0xBE], [0xEF, 0xBF, 0xBF],
                                          [0xF0, 0x9F, 0xBF, 0xBE], [0xEF, 0xB7, 0x90]]
        let invalidTitles = ["", " ", " Bad", "Bad\nTitle", "Bad\u{202E}Title",
                             String(repeating: "A", count: 81), String(repeating: "é", count: 81)] +
                            xmlNoncharacters.map { "Bad" + String(decoding: $0, as: UTF8.self) + "Title" }
        for title in invalidTitles {
            XCTAssertThrowsError(try NativeDLNA.didlMetadata(media: media, title: title))
        }
        XCTAssertThrowsError(try NativeDLNA.request(.play, endpoint: endpoint, metadataTitle: "Owned"))
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
        let playing = try await NativeDLNA.queryState(endpoint: endpoint)
        XCTAssertEqual(playing, .playing)
        try await NativeDLNA.send(.pause, endpoint: endpoint)
        let paused = try await NativeDLNA.queryState(endpoint: endpoint)
        XCTAssertEqual(paused, .pausedPlayback)
        try await NativeDLNA.send(.stop, endpoint: endpoint)
        let stopped = try await NativeDLNA.queryState(endpoint: endpoint)
        XCTAssertEqual(stopped, .stopped)
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
    func testTransportStateRequiresSingleDirectBoundedKnownValue() throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        func soap(_ content: String) -> Data {
            Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:GetTransportInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">\(content)</u:GetTransportInfoResponse></s:Body></s:Envelope>".utf8)
        }
        for (value, expected) in [("PLAYING", NativeDLNATransportState.playing),
                                  ("PAUSED_PLAYBACK", .pausedPlayback),
                                  ("STOPPED", .stopped),
                                  ("NO_MEDIA_PRESENT", .noMediaPresent)] {
            XCTAssertEqual(try NativeDLNA.parseStateResponse(soap("<CurrentTransportState>\(value)</CurrentTransportState>"), response: response), expected)
        }
        XCTAssertEqual(try NativeDLNA.parseStateResponse(soap("<CurrentTransportState><![CDATA[PLAYING]]></CurrentTransportState>"), response: response), .playing)
        for invalid in [
            "",
            "<CurrentTransportState>PLAYING<![CDATA[INVALID]]></CurrentTransportState>",
            "<CurrentTransportState>UNKNOWN</CurrentTransportState>",
            "<CurrentTransportState>PLAYING</CurrentTransportState><CurrentTransportState>STOPPED</CurrentTransportState>",
            "<Extra><CurrentTransportState>PLAYING</CurrentTransportState></Extra>",
            "<x:CurrentTransportState xmlns:x=\"urn:untrusted\">PLAYING</x:CurrentTransportState>",
            "<CurrentTransportState><Nested>PLAYING</Nested></CurrentTransportState>",
            "<CurrentTransportState>\(String(repeating: "A", count: 65))</CurrentTransportState>"
        ] {
            XCTAssertThrowsError(try NativeDLNA.parseStateResponse(soap(invalid), response: response), "Accepted invalid state: \(invalid)")
        }
        let wrong = Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:PlayResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><CurrentTransportState>PLAYING</CurrentTransportState></u:PlayResponse></s:Body></s:Envelope>".utf8)
        XCTAssertThrowsError(try NativeDLNA.parseStateResponse(wrong, response: response))
        XCTAssertThrowsError(try NativeDLNA.parseStateResponse(Data(repeating: 65, count: 32769), response: response))
    }

    func testPositionInfoRejectsMalformedAndSpoofedValues() throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        func soap(_ fields: String) -> Data {
            Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:GetPositionInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">\(fields)</u:GetPositionInfoResponse></s:Body></s:Envelope>".utf8)
        }
        let valid = try NativeDLNA.parsePositionResponse(
            soap("<TrackDuration>00:02:00</TrackDuration><RelTime>00:00:42</RelTime>"), response: response)
        XCTAssertEqual(valid, NativeDLNAPosition(seconds: 42, durationSeconds: 120))
        XCTAssertEqual(valid.localizedLabel, "00:00:42 / 00:02:00")
        let unknown = try NativeDLNA.parsePositionResponse(
            soap("<TrackDuration>NOT_IMPLEMENTED</TrackDuration><RelTime><![CDATA[00:00:42]]></RelTime>"), response: response)
        XCTAssertNil(unknown.durationSeconds)
        for invalid in [
            "<TrackDuration>00:02:00</TrackDuration>",
            "<RelTime>00:00:42</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>00:00:42</RelTime><RelTime>00:00:41</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>00:02:01</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>00:60:00</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>NOT_IMPLEMENTED</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>00:00:42<![CDATA[99]]></RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><x:RelTime xmlns:x=\"urn:foreign\">00:00:42</x:RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><Wrapper><RelTime>00:00:42</RelTime></Wrapper>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>\(String(repeating: "1", count: 64))</RelTime>"
        ] {
            XCTAssertThrowsError(try NativeDLNA.parsePositionResponse(soap(invalid), response: response), invalid)
        }
    }

    func testBoundedSeekTargetAndInvalidInput() throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let request = try NativeDLNA.request(.seek, endpoint: endpoint, seekSeconds: 57)
        XCTAssertEqual(request.value(forHTTPHeaderField: "SOAPACTION"),
                       "\"urn:schemas-upnp-org:service:AVTransport:1#Seek\"")
        XCTAssertTrue(String(decoding: request.httpBody!, as: UTF8.self)
            .contains("<Unit>REL_TIME</Unit><Target>00:00:57</Target>"))
        for value in [-1, 360000, Int.max] {
            XCTAssertThrowsError(try NativeDLNA.request(.seek, endpoint: endpoint, seekSeconds: value))
        }
        XCTAssertThrowsError(try NativeDLNA.request(.seek, endpoint: endpoint))
        XCTAssertEqual(try NativeDLNASeek.relativeTarget(
            position: NativeDLNAPosition(seconds: 2, durationSeconds: 120), deltaSeconds: -15), 0)
        XCTAssertEqual(try NativeDLNASeek.relativeTarget(
            position: NativeDLNAPosition(seconds: 119, durationSeconds: 120), deltaSeconds: 15), 120)
        XCTAssertThrowsError(try NativeDLNASeek.relativeTarget(
            position: NativeDLNAPosition(seconds: 0, durationSeconds: nil), deltaSeconds: 15))
        XCTAssertThrowsError(try NativeDLNASeek.relativeTarget(
            position: NativeDLNAPosition(seconds: 0, durationSeconds: 0), deltaSeconds: 15))
        XCTAssertThrowsError(try NativeDLNASeek.relativeTarget(
            position: NativeDLNAPosition(seconds: 42, durationSeconds: 120), deltaSeconds: Int.max))
    }

    func testOwnedLoopbackRelativeSeekAndStoppedRejection() async throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        try await NativeDLNA.cast(endpoint: endpoint, media: media)
        let forward = try await NativeDLNA.seekRelative(endpoint: endpoint, deltaSeconds: 15)
        XCTAssertEqual(forward, 57)
        let afterForward = try await NativeDLNA.queryPosition(endpoint: endpoint)
        XCTAssertEqual(afterForward.seconds, 57)
        let backward = try await NativeDLNA.seekRelative(endpoint: endpoint, deltaSeconds: -15)
        XCTAssertEqual(backward, 42)
        try await NativeDLNA.send(.stop, endpoint: endpoint)
        do {
            _ = try await NativeDLNA.seekRelative(endpoint: endpoint, deltaSeconds: 15)
            XCTFail("Seek succeeded on stopped renderer")
        } catch NativeDLNAError.unsupportedSeek { }
    }

    func testPositionInfoOwnedLoopbackQuery() async throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        try await NativeDLNA.cast(endpoint: endpoint, media: media)
        let position = try await NativeDLNA.queryPosition(endpoint: endpoint)
        XCTAssertEqual(position.seconds, 42)
        XCTAssertEqual(position.durationSeconds, 120)
    }


    func testResumeRequiresFreshPausedState() async throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        try await NativeDLNA.send(.stop, endpoint: endpoint)
        do {
            try await NativeDLNA.resumePaused(endpoint: endpoint)
            XCTFail("Stopped renderer was resumed")
        } catch NativeDLNAError.unsupportedResume { }

        try await NativeDLNA.cast(endpoint: endpoint, media: media)
        do {
            try await NativeDLNA.resumePaused(endpoint: endpoint)
            XCTFail("Already-playing renderer was resumed")
        } catch NativeDLNAError.unsupportedResume { }

        try await NativeDLNA.send(.pause, endpoint: endpoint)
        let pausedState = try await NativeDLNA.queryState(endpoint: endpoint)
        XCTAssertEqual(pausedState, .pausedPlayback)
        try await NativeDLNA.resumePaused(endpoint: endpoint)
        let resumedState = try await NativeDLNA.queryState(endpoint: endpoint)
        XCTAssertEqual(resumedState, .playing)
    }


    func testImportedUPnPFriendlyNameIsBoundedAndNeverChangesControlOrigin() throws {
        let source = try NativeDLNADescription.location("http://127.0.0.1:8768/device.xml")
        let namespace = NativeDLNADescription.deviceNamespace
        func description(_ name: String) -> Data {
            Data("<root xmlns=\"\(namespace)\"><device>\(name)<serviceList><service><serviceType>\(NativeDLNA.service)</serviceType><controlURL>/upnp/control/AVTransport1</controlURL></service></serviceList></device></root>".utf8)
        }
        let named = try NativeDLNADescription.parseDetails(
            description("<friendlyName>客厅电视 TV-Next</friendlyName>"), location: source)
        XCTAssertEqual(named.friendlyName, "客厅电视 TV-Next")
        XCTAssertEqual(named.controlURL.absoluteString, "http://127.0.0.1:8768/upnp/control/AVTransport1")
        XCTAssertNil(try NativeDLNADescription.parseDetails(description(""), location: source).friendlyName)
        let invalid = [
            "<friendlyName>One</friendlyName><friendlyName>Two</friendlyName>",
            "<friendlyName><child>Fake</child></friendlyName>",
            "<x:friendlyName xmlns:x=\"urn:foreign\">Forged</x:friendlyName>",
            "<friendlyName>Bad\u{202E}Name</friendlyName>",
            "<friendlyName>Bad\nName</friendlyName>",
            "<friendlyName>\(String(repeating: "A", count: 161))</friendlyName>"
        ]
        for value in invalid {
            XCTAssertThrowsError(try NativeDLNADescription.parseDetails(description(value), location: source),
                                 "Accepted unsafe friendlyName")
        }
    }

    func testOptionalUPnPModelNameIsDisplayOnlyAndBounded() throws {
        let source = try NativeDLNADescription.location("http://127.0.0.1:8768/device.xml")
        let ns = NativeDLNADescription.deviceNamespace
        func xml(_ model: String) -> Data {
            Data("<root xmlns=\"\(ns)\"><device><friendlyName>Living Room</friendlyName>\(model)<serviceList><service><serviceType>\(NativeDLNA.service)</serviceType><controlURL>/upnp/control/AVTransport1</controlURL></service></serviceList></device></root>".utf8)
        }
        let valid = try NativeDLNADescription.parseDetails(xml("<modelName>TV-Next Model 1</modelName>"), location: source)
        XCTAssertEqual(valid.friendlyName, "Living Room")
        XCTAssertEqual(valid.modelName, "TV-Next Model 1")
        XCTAssertEqual(valid.controlURL.absoluteString, "http://127.0.0.1:8768/upnp/control/AVTransport1")
        XCTAssertNil(try NativeDLNADescription.parseDetails(xml(""), location: source).modelName)
        XCTAssertNil(try NativeDLNADescription.parseDetails(xml("<modelName/>"), location: source).modelName)
        let boundary = try NativeDLNADescription.parseDetails(
            xml("<modelName>\(String(repeating: "é", count: 80))</modelName>"), location: source)
        XCTAssertEqual(boundary.modelName?.utf8.count, 160)
        let twoDevices = Data("<root xmlns=\"\(ns)\"><device><friendlyName>First</friendlyName></device><device><modelName>Second</modelName><serviceList><service><serviceType>\(NativeDLNA.service)</serviceType><controlURL>/upnp/control/AVTransport1</controlURL></service></serviceList></device></root>".utf8)
        XCTAssertThrowsError(try NativeDLNADescription.parseDetails(twoDevices, location: source),
                             "A name from one root device must not be paired with another device's control URL")
        for bad in [
            "<modelName>One</modelName><modelName>Two</modelName>",
            "<modelName>TV<child/>Next</modelName>",
            "<x:modelName xmlns:x=\"urn:foreign\">Spoof</x:modelName>",
            "<modelName>Bad\u{202E}Name</modelName>",
            "<modelName>Bad\nName</modelName>",
            "<modelName>\(String(repeating: "é", count: 81))</modelName>"
        ] {
            XCTAssertThrowsError(try NativeDLNADescription.parseDetails(xml(bad), location: source),
                                 "Accepted untrusted modelName: \(bad)")
        }
    }

    func testDeviceDescriptionParserRejectsAmbiguousAndForeignControlURLs() throws {
        let source = try NativeDLNADescription.location("http://127.0.0.1:8768/device.xml")
        func xml(_ services: String) -> Data {
            Data("<root xmlns=\"urn:schemas-upnp-org:device-1-0\"><device><serviceList>\(services)</serviceList></device></root>".utf8)
        }
        func service(_ control: String) -> String {
            "<service><serviceType>\(NativeDLNA.service)</serviceType><controlURL>\(control)</controlURL></service>"
        }
        let good = try NativeDLNADescription.parse(xml(service("/upnp/control/AVTransport1")), location: source)
        XCTAssertEqual(good.absoluteString, "http://127.0.0.1:8768/upnp/control/AVTransport1")
        for value in ["http://8.8.8.8:8768/AVTransport", "http://127.0.0.1:9999/AVTransport",
                      "/../admin", "/upnp/%2e%2e/admin", "//127.0.0.1:8768/admin",
                      "/upnp/control?secret=x", "file:///private/secret"] {
            XCTAssertThrowsError(try NativeDLNADescription.parse(xml(service(value)), location: source))
        }
        XCTAssertThrowsError(try NativeDLNADescription.parse(xml(service("/a") + service("/b")), location: source))
        XCTAssertThrowsError(try NativeDLNADescription.parse(xml(service("<nested>/a</nested>")), location: source))
        XCTAssertThrowsError(try NativeDLNADescription.parse(
            Data("<!DOCTYPE root [<!ENTITY secret SYSTEM \"file:///etc/passwd\">]>".utf8) +
                xml(service("/upnp/control/AVTransport1")), location: source))
    }

    func testOwnedDeviceDescriptionImportNeverFollowsExternalURL() async throws {
        let imported = try await NativeDLNADescription.load("http://127.0.0.1:8768/device.xml")
        XCTAssertEqual(imported.absoluteString, "http://127.0.0.1:8768/upnp/control/AVTransport1")
        do {
            _ = try await NativeDLNADescription.load("http://127.0.0.1:8768/device-foreign.xml")
            XCTFail("Accepted public AVTransport URL")
        } catch NativeDLNAError.invalidDescription { }
        do {
            _ = try await NativeDLNADescription.load("http://127.0.0.1:8768/device-redirect")
            XCTFail("Followed redirect to untrusted device description")
        } catch NativeDLNAError.httpStatus(let status) { XCTAssertEqual(status, 302) }
        do {
            _ = try await NativeDLNADescription.load("http://127.0.0.1:8768/device-oversize")
            XCTFail("Accepted oversized XML")
        } catch NativeDLNAError.responseTooLarge { }
    }

}
