import Foundation

/// Converts a previously parsed SSDP response into a verified candidate only
/// after a bounded device-description read. It never starts discovery or SOAP.
enum NativeSSDPResolver {
    /// Reject caller-constructed candidates before any HTTP request. The UDP
    /// parser checks the sender/LOCATION binding; repeat independent origin,
    /// target and USN checks at the network request boundary.
    static func validatedLocation(_ candidate: NativeSSDPResponse.Candidate) throws -> URL {
        guard let location = try? NativeDLNADescription.location(candidate.location.absoluteString),
              location == candidate.location,
              let host = location.host, !host.hasPrefix("127."),
              candidate.serviceType == NativeSSDPResponse.mediaRenderer ||
                candidate.serviceType == NativeSSDPResponse.avTransport else {
            throw NativeDLNAError.invalidDescription
        }
        let suffix = "::" + candidate.serviceType
        guard candidate.uniqueServiceName.hasSuffix(suffix) else {
            throw NativeDLNAError.invalidDescription
        }
        let identity = String(candidate.uniqueServiceName.dropLast(suffix.count))
        guard identity.hasPrefix("uuid:"), identity.utf8.count <= 128,
              identity.utf8.count > 5,
              identity.utf8.dropFirst(5).allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) ||
                  (48...57).contains($0) || $0 == 45 || $0 == 46 || $0 == 95
              }),
              NativeSSDPResponse.matchesDescriptionUDN(candidate, udn: identity) else {
            throw NativeDLNAError.invalidDescription
        }
        return location
    }

    /// Production path: the existing GET enforces an eight-second deadline,
    /// 32-KiB streamed cap, no redirects/cookies/proxies and strict UPnP XML.
    static func resolve(_ candidate: NativeSSDPResponse.Candidate) async throws -> NativeDLNADescription.Details {
        try await resolve(candidate, fetch: { location in
            try await NativeDLNADescription.loadDetails(location.absoluteString)
        })
    }

    /// Injected loader is for owned fixtures; security checks run before and
    /// after it. A matching self-asserted UDN is not device authentication.
    static func resolve(
        _ candidate: NativeSSDPResponse.Candidate,
        fetch: (URL) async throws -> NativeDLNADescription.Details
    ) async throws -> NativeDLNADescription.Details {
        try Task.checkCancellation()
        let location = try validatedLocation(candidate)
        let details = try await fetch(location)
        try Task.checkCancellation()
        guard let control = try? NativeDLNA.rendererURL(details.controlURL.absoluteString),
              control == details.controlURL,
              control.scheme == location.scheme,
              control.host == location.host,
              control.port == location.port,
              NativeSSDPResponse.matchesDescriptionUDN(candidate, udn: details.deviceUDN) else {
            throw NativeDLNAError.invalidDescription
        }
        return details
    }
}
