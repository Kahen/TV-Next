import Foundation

@main
struct SSDPResolverSmoke {
    static func main() async throws {
        let target = NativeSSDPResponse.mediaRenderer
        let location = URL(string: "http://192.168.1.20:1400/device.xml")!
        let candidate = NativeSSDPResponse.Candidate(
            location: location, serviceType: target,
            uniqueServiceName: "uuid:owned-123::" + target)
        let xml = Data("""
        <root xmlns="urn:schemas-upnp-org:device-1-0"><device>
        <UDN>uuid:Owned-123</UDN><friendlyName>Owned Renderer</friendlyName>
        <serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/upnp/control</controlURL></service></serviceList>
        </device></root>
        """.utf8)
        let details = try NativeDLNADescription.parseDetails(xml, location: location)
        var calls = 0
        let resolved = try await NativeSSDPResolver.resolve(candidate, fetch: { requested in
            precondition(requested == location)
            calls += 1
            return details
        })
        precondition(calls == 1 && resolved == details)
        precondition(resolved.deviceUDN == "uuid:Owned-123")
        precondition(resolved.controlURL.absoluteString == "http://192.168.1.20:1400/upnp/control")

        let invalidCandidates: [NativeSSDPResponse.Candidate] = [
            .init(location: URL(string: "http://127.0.0.1:1400/device.xml")!,
                  serviceType: target, uniqueServiceName: candidate.uniqueServiceName),
            .init(location: URL(string: "http://8.8.8.8:1400/device.xml")!,
                  serviceType: target, uniqueServiceName: candidate.uniqueServiceName),
            .init(location: URL(string: "http://192.168.1.20:1400/device%2Fxml")!,
                  serviceType: target, uniqueServiceName: candidate.uniqueServiceName),
            .init(location: location, serviceType: "ssdp:all",
                  uniqueServiceName: "uuid:owned-123::ssdp:all"),
            .init(location: location, serviceType: target,
                  uniqueServiceName: "uuid:owned-123::" + NativeSSDPResponse.avTransport),
            .init(location: location, serviceType: target,
                  uniqueServiceName: "uuid:bad identity::" + target),
            .init(location: location, serviceType: target,
                  uniqueServiceName: "uuid:" + String(repeating: "a", count: 124) + "::" + target)
        ]
        for invalid in invalidCandidates {
            var fetched = false
            do {
                _ = try await NativeSSDPResolver.resolve(invalid, fetch: { _ in
                    fetched = true
                    return details
                })
                fatalError("Accepted unsafe discovery candidate")
            } catch NativeDLNAError.invalidDescription {}
            precondition(!fetched, "Unsafe candidate triggered network fetch")
        }

        let invalidDetails: [NativeDLNADescription.Details] = [
            .init(controlURL: details.controlURL, friendlyName: nil,
                  modelName: nil, deviceUDN: nil),
            .init(controlURL: details.controlURL, friendlyName: nil,
                  modelName: nil, deviceUDN: "uuid:other"),
            .init(controlURL: URL(string: "http://192.168.1.21:1400/upnp/control")!,
                  friendlyName: nil, modelName: nil, deviceUDN: "uuid:owned-123"),
            .init(controlURL: URL(string: "http://192.168.1.20:1401/upnp/control")!,
                  friendlyName: nil, modelName: nil, deviceUDN: "uuid:owned-123")
        ]
        for invalid in invalidDetails {
            do {
                _ = try await NativeSSDPResolver.resolve(candidate, fetch: { _ in invalid })
                fatalError("Accepted forged device description")
            } catch NativeDLNAError.invalidDescription {}
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeSSDPResolver.resolve(candidate, fetch: { _ in
                fatalError("Cancelled discovery performed network fetch")
            })
        }
        do { _ = try await cancelled.value; fatalError("Accepted cancelled discovery") }
        catch is CancellationError {}

        print("SSDP candidate preflight, UDN binding, same-origin, cancellation and no-fetch negative tests passed")
    }
}
