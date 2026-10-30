import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct DLNANetworkSmoke {
    static func main() async throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        try await NativeDLNA.cast(endpoint: endpoint, media: media)
        try await NativeDLNA.send(.pause, endpoint: endpoint)
        try await NativeDLNA.send(.stop, endpoint: endpoint)
        for (path, status) in [("redirect", 302), ("fault", 500)] {
            let bad = try NativeDLNA.rendererURL("http://127.0.0.1:8768/\(path)")
            do { try await NativeDLNA.send(.play, endpoint: bad); fatalError("Accepted \(path)") }
            catch NativeDLNAError.httpStatus(let received) { precondition(received == status) }
        }
        let oversized = try NativeDLNA.rendererURL("http://127.0.0.1:8768/oversize")
        do { try await NativeDLNA.send(.play, endpoint: oversized); fatalError("Accepted oversized response") }
        catch NativeDLNAError.responseTooLarge { }
        print("Native manual DLNA loopback SOAP/redirect/size-cap integration passed")
    }
}
