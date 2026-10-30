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
        print("Native manual DLNA SOAP and private endpoint contract passed")
    }
}
