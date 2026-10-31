import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct DLNASmoke {
    static func main() throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/video.mp4?a=1&b=2")
        let set = try NativeDLNA.request(.setURI, endpoint: endpoint, media: media)
        precondition(String(decoding: set.httpBody!, as: UTF8.self).contains("a=1&amp;b=2"))
        precondition(set.value(forHTTPHeaderField: "SOAPACTION") == "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"")
        precondition(String(decoding: set.httpBody!, as: UTF8.self).contains("<CurrentURIMetaData></CurrentURIMetaData>"))
        let withMetadata = try NativeDLNA.request(.setURI, endpoint: endpoint, media: media, metadataTitle: "Owned & <Demo>")
        let withMetadataBody = String(decoding: withMetadata.httpBody!, as: UTF8.self)
        precondition(withMetadataBody.contains("&lt;DIDL-Lite"))
        precondition(withMetadataBody.contains("Owned &amp;amp; &amp;lt;Demo&amp;gt;"))
        precondition(withMetadataBody.contains("a=1&amp;amp;b=2"))
        for invalid in ["", " ", "Bad\nTitle", "Bad\u{202E}Title", String(repeating: "A", count: 81), String(repeating: "é", count: 81), "Bad\u{FFFE}Title", "Bad\u{FFFF}Title", "Bad\u{1FFFE}Title", "Bad\u{FDD0}Title"] {
            do { _ = try NativeDLNA.request(.setURI, endpoint: endpoint, media: media, metadataTitle: invalid); fatalError("Accepted unsafe DIDL title") }
            catch NativeDLNAError.invalidMetadata { }
        }
        do { _ = try NativeDLNA.request(.play, endpoint: endpoint, metadataTitle: "Unexpected"); fatalError("Accepted metadata on Play") }
        catch NativeDLNAError.invalidMetadata { }
        let seek = try NativeDLNA.request(.seek, endpoint: endpoint, seekSeconds: 57)
        precondition(seek.value(forHTTPHeaderField: "SOAPACTION") == "\"urn:schemas-upnp-org:service:AVTransport:1#Seek\"")
        precondition(String(decoding: seek.httpBody!, as: UTF8.self).contains("<Unit>REL_TIME</Unit><Target>00:00:57</Target>"))
        for bad in [-1, 360000, Int.max] {
            do { _ = try NativeDLNA.request(.seek, endpoint: endpoint, seekSeconds: bad); fatalError("Accepted invalid seek") }
            catch NativeDLNAError.invalidSeek { }
        }
        do { _ = try NativeDLNA.request(.seek, endpoint: endpoint); fatalError("Accepted missing target") }
        catch NativeDLNAError.invalidSeek { }
        let forwardTarget = try NativeDLNASeek.relativeTarget(position: NativeDLNAPosition(seconds: 42, durationSeconds: 120), deltaSeconds: 15)
        precondition(forwardTarget == 57)
        let lowerBound = try NativeDLNASeek.relativeTarget(position: NativeDLNAPosition(seconds: 4, durationSeconds: 120), deltaSeconds: -15)
        precondition(lowerBound == 0)
        let upperBound = try NativeDLNASeek.relativeTarget(position: NativeDLNAPosition(seconds: 119, durationSeconds: 120), deltaSeconds: 15)
        precondition(upperBound == 120)
        for position in [NativeDLNAPosition(seconds: 10, durationSeconds: nil), NativeDLNAPosition(seconds: 0, durationSeconds: 0)] {
            do { _ = try NativeDLNASeek.relativeTarget(position: position, deltaSeconds: 15); fatalError("Accepted nonfinite seek") }
            catch NativeDLNAError.unsupportedSeek { }
        }
        do { _ = try NativeDLNASeek.relativeTarget(position: NativeDLNAPosition(seconds: 42, durationSeconds: 120), deltaSeconds: Int.max); fatalError("Accepted unbounded delta") }
        catch NativeDLNAError.invalidSeek { }
        let absolute90 = try NativeDLNASeek.parseAbsolute("00:01:30")
        let absoluteMax = try NativeDLNASeek.parseAbsolute("99:59:59")
        let absoluteZero = try NativeDLNASeek.parseAbsolute("00:00:00")
        precondition(absolute90 == 90 && absoluteMax == NativeDLNASeek.maxSeconds && absoluteZero == 0)
        for invalid in ["0:01:30", "00:60:00", "00:00:60", "100:00:00",
                        "00:01:3a", " 00:01:30", "00:01:30 ", "００:０１:３０",
                        "00:01:30\n", "-1:00:00"] {
            do { _ = try NativeDLNASeek.parseAbsolute(invalid); fatalError("Accepted malformed absolute time") }
            catch NativeDLNAError.invalidSeek { }
        }
        let finite = NativeDLNAPosition(seconds: 42, durationSeconds: 120)
        let absoluteStart = try NativeDLNASeek.absoluteTarget(position: finite, requestedSeconds: 0)
        let absoluteEnd = try NativeDLNASeek.absoluteTarget(position: finite, requestedSeconds: 120)
        precondition(absoluteStart == 0 && absoluteEnd == 120)
        for invalid in [-1, 121, Int.max] {
            do { _ = try NativeDLNASeek.absoluteTarget(position: finite, requestedSeconds: invalid); fatalError("Accepted out-of-duration absolute seek") }
            catch NativeDLNAError.invalidSeek { }
        }
        do {
            _ = try NativeDLNASeek.absoluteTarget(position: NativeDLNAPosition(seconds: 42, durationSeconds: nil), requestedSeconds: 30)
            fatalError("Accepted unknown-duration absolute seek")
        } catch NativeDLNAError.unsupportedSeek { }
        let pause = try NativeDLNA.request(.pause, endpoint: endpoint)
        precondition(String(decoding: pause.httpBody!, as: UTF8.self).contains("<u:Pause"))
        for invalid in ["https://192.168.1.2:1400/upnp", "http://8.8.8.8:1400/upnp", "http://example.com:1400/upnp", "http://192.168.1.2:1400/", "http://user:pw@192.168.1.2:1400/upnp", "http://192.168.1.2:1400/upnp?x=1", "http://192.168.1.2:1400/upnp/%2e%2e/admin", "http://192.168.1.2:1400/upnp#fragment", "http://192.168.1.02:1400/upnp"] {
            do { _ = try NativeDLNA.rendererURL(invalid); fatalError("accepted unsafe renderer \(invalid)") }
            catch NativeDLNAError.invalidRenderer { }
        }
        for invalid in ["file:///tmp/a.mp4", "javascript:alert(1)", "https://user:pw@media.example/owned.mp4", "https://media.example/video.mp4#fragment"] {
            do { _ = try NativeDLNA.mediaURL(invalid); fatalError("accepted unsafe media \(invalid)") }
            catch NativeDLNAError.invalidMedia { }
        }
        do { _ = try NativeDLNA.mediaURL("https://media.example/a.mp4", hasHeaders: true); fatalError("accepted headers") }
        catch NativeDLNAError.unsupportedMedia { }
        let ok = Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:PlayResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/></s:Body></s:Envelope>".utf8)
        let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        try NativeDLNA.validate(ok, response: response, action: .play)
        for invalid in [Data("<html>ok</html>".utf8), Data("<s:Fault>bad</s:Fault><u:PlayResponse/>http://schemas.xmlsoap.org/soap/envelope/".utf8), Data(repeating: 65, count: 32769)] {
            do { try NativeDLNA.validate(invalid, response: response, action: .play); fatalError("accepted invalid SOAP") }
            catch { }
        }
        let query = try NativeDLNA.request(.getTransportInfo, endpoint: endpoint)
        precondition(query.value(forHTTPHeaderField: "SOAPACTION") == "\"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo\"")
        let stateSOAP = Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:GetTransportInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><CurrentTransportState>PLAYING</CurrentTransportState></u:GetTransportInfoResponse></s:Body></s:Envelope>".utf8)
        let reportedState = try NativeDLNA.parseStateResponse(stateSOAP, response: response)
        precondition(reportedState == .playing)
        let cdata = Data(String(decoding: stateSOAP, as: UTF8.self).replacingOccurrences(of: ">PLAYING<", with: "><![CDATA[PLAYING]]><").utf8)
        let cdataState = try NativeDLNA.parseStateResponse(cdata, response: response)
        precondition(cdataState == .playing)
        let spoofed = Data(String(decoding: stateSOAP, as: UTF8.self).replacingOccurrences(of: ">PLAYING<", with: ">PLAYING<![CDATA[INVALID]]><").utf8)
        do { _ = try NativeDLNA.parseStateResponse(spoofed, response: response); fatalError("Accepted mixed CDATA spoof") }
        catch NativeDLNAError.invalidResponse { }
        let missing = Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:GetTransportInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/></s:Body></s:Envelope>".utf8)
        do { _ = try NativeDLNA.parseStateResponse(missing, response: response); fatalError("Accepted missing state") }
        catch NativeDLNAError.invalidResponse { }
        let positionRequest = try NativeDLNA.request(.getPositionInfo, endpoint: endpoint)
        precondition(positionRequest.value(forHTTPHeaderField: "SOAPACTION") == "\"urn:schemas-upnp-org:service:AVTransport:1#GetPositionInfo\"")
        func positionSOAP(_ fields: String) -> Data {
            Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:GetPositionInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">\(fields)</u:GetPositionInfoResponse></s:Body></s:Envelope>".utf8)
        }
        let good = try NativeDLNA.parsePositionResponse(positionSOAP("<TrackDuration>00:02:00</TrackDuration><RelTime>00:00:42</RelTime>"), response: response)
        precondition(good == NativeDLNAPosition(seconds: 42, durationSeconds: 120))
        precondition(good.localizedLabel == "00:00:42 / 00:02:00")
        let unknown = try NativeDLNA.parsePositionResponse(positionSOAP("<TrackDuration>NOT_IMPLEMENTED</TrackDuration><RelTime><![CDATA[00:00:42]]></RelTime>"), response: response)
        precondition(unknown.durationSeconds == nil && unknown.seconds == 42)
        for bad in [
            "<TrackDuration>00:02:00</TrackDuration>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>NOT_IMPLEMENTED</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>00:60:00</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>00:02:01</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>00:00:42</RelTime><RelTime>00:00:41</RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><RelTime>00:00:42<![CDATA[99]]></RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><x:RelTime xmlns:x=\"urn:untrusted\">00:00:42</x:RelTime>",
            "<TrackDuration>00:02:00</TrackDuration><Outer><RelTime>00:00:42</RelTime></Outer>"
        ] {
            do { _ = try NativeDLNA.parsePositionResponse(positionSOAP(bad), response: response); fatalError("Accepted malformed position") }
            catch NativeDLNAError.invalidResponse { }
        }
        print("Native manual DLNA SOAP and private endpoint contract passed")
    }
}
