import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct DLNADescriptionNetworkSmoke {
    static func main() async throws {
        let control = try await NativeDLNADescription.load("http://127.0.0.1:8768/device.xml")
        precondition(control.absoluteString == "http://127.0.0.1:8768/upnp/control/AVTransport1")
        for path in ["device-foreign.xml", "device-duplicate.xml", "device-missing.xml", "device-doctype.xml"] {
            do {
                _ = try await NativeDLNADescription.load("http://127.0.0.1:8768/\(path)")
                fatalError("Accepted invalid LAN description \(path)")
            } catch NativeDLNAError.invalidDescription { }
        }
        do {
            _ = try await NativeDLNADescription.load("http://127.0.0.1:8768/device-redirect")
            fatalError("Followed device description redirect")
        } catch NativeDLNAError.httpStatus(let status) { precondition(status == 302) }
        do {
            _ = try await NativeDLNADescription.load("http://127.0.0.1:8768/device-oversize")
            fatalError("Accepted oversized description")
        } catch NativeDLNAError.responseTooLarge { }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeDLNADescription.load("http://127.0.0.1:8768/device.xml")
        }
        do { _ = try await cancelled.value; fatalError("Accepted pre-cancelled import") }
        catch is CancellationError { }
        print("Owned localhost UPnP description GET/redirect/size/cancellation integration passed")
    }
}
