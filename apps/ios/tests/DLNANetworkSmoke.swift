import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct DLNANetworkSmoke {
    static func main() async throws {
        let endpoint = try NativeDLNA.rendererURL("http://127.0.0.1:8768/upnp/control/AVTransport1")
        let media = try NativeDLNA.mediaURL("https://media.example/owned.mp4?a=1&b=2")
        let alreadyCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await NativeDLNA.send(.play, endpoint: endpoint)
        }
        do { try await alreadyCancelled.value; fatalError("Pre-cancelled task succeeded") }
        catch is CancellationError { }
        try await NativeDLNA.cast(endpoint: endpoint, media: media)
        let playing = try await NativeDLNA.queryState(endpoint: endpoint)
        precondition(playing == .playing)
        try await NativeDLNA.send(.pause, endpoint: endpoint)
        let paused = try await NativeDLNA.queryState(endpoint: endpoint)
        precondition(paused == .pausedPlayback)
        try await NativeDLNA.send(.stop, endpoint: endpoint)
        let stopped = try await NativeDLNA.queryState(endpoint: endpoint)
        precondition(stopped == .stopped)
        for (path, status) in [("redirect", 302), ("fault", 500)] {
            let bad = try NativeDLNA.rendererURL("http://127.0.0.1:8768/\(path)")
            do { try await NativeDLNA.send(.play, endpoint: bad); fatalError("Accepted \(path)") }
            catch NativeDLNAError.httpStatus(let received) { precondition(received == status) }
        }
        let oversized = try NativeDLNA.rendererURL("http://127.0.0.1:8768/oversize")
        do { try await NativeDLNA.send(.play, endpoint: oversized); fatalError("Accepted oversized response") }
        catch NativeDLNAError.responseTooLarge { }
        let slow = try NativeDLNA.rendererURL("http://127.0.0.1:8768/slow")
        let start = Date()
        do { try await NativeDLNA.send(.play, endpoint: slow); fatalError("Accepted slow response") }
        catch { precondition(Date().timeIntervalSince(start) < 11, "Response deadline exceeded") }
        print("Native manual DLNA loopback SOAP/redirect/size-cap/cancellation/deadline integration passed")
    }
}
