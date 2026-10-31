import Foundation

/// Bounded, non-networking parser for an explicitly requested SSDP M-SEARCH response.
/// This does not send multicast, discover devices, or approve a renderer for playback.
enum NativeSSDPResponse {
    struct Candidate: Equatable {
        let location: URL
        let serviceType: String
        let uniqueServiceName: String
    }

    enum ValidationError: Error, Equatable {
        case malformed
        case unsupportedTarget
        case unsafeLocation
    }

    static let mediaRenderer = "urn:schemas-upnp-org:device:MediaRenderer:1"
    static let avTransport = "urn:schemas-upnp-org:service:AVTransport:1"
    static let maxDatagramBytes = 4096
    private static let maxHeaders = 24

    static func parse(_ datagram: Data, senderIPv4: String) throws -> Candidate {
        guard !datagram.isEmpty, datagram.count <= maxDatagramBytes,
              datagram.allSatisfy({ $0 == 13 || $0 == 10 || (32...126).contains($0) }),
              let message = String(data: datagram, encoding: .ascii),
              message.hasSuffix("\r\n\r\n") else { throw ValidationError.malformed }
        // Reject lone CR/LF as well as folded headers and trailing bodies.
        let bytes = Array(datagram)
        guard bytes.indices.allSatisfy({ i in
            if bytes[i] == 13 { return i + 1 < bytes.count && bytes[i + 1] == 10 }
            if bytes[i] == 10 { return i > 0 && bytes[i - 1] == 13 }
            return true
        }) else { throw ValidationError.malformed }
        let lines = message.components(separatedBy: "\r\n")
        guard lines.count >= 5, lines.suffix(2).allSatisfy({ $0.isEmpty }),
              lines[0] == "HTTP/1.1 200 OK" else { throw ValidationError.malformed }
        var headers: [String: String] = [:]
        for line in lines.dropFirst().dropLast(2) {
            guard !line.isEmpty, !line.hasPrefix(" "), !line.hasPrefix("\t"),
                  let colon = line.firstIndex(of: ":") else { throw ValidationError.malformed }
            let name = String(line[..<colon])
            guard !name.isEmpty, name.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
            }) else { throw ValidationError.malformed }
            let key = name.lowercased()
            guard headers.count < maxHeaders, headers[key] == nil else { throw ValidationError.malformed }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.count <= 512 else { throw ValidationError.malformed }
            headers[key] = value
        }
        guard let st = headers["st"], st == mediaRenderer || st == avTransport else {
            throw ValidationError.unsupportedTarget
        }
        guard let usn = headers["usn"], usn.utf8.count <= 256,
              usn.hasPrefix("uuid:"), usn.hasSuffix("::" + st),
              let separator = usn.range(of: "::"),
              usn[separator.upperBound...] == st,
              !usn[..<separator.lowerBound].dropFirst(5).isEmpty,
              usn[..<separator.lowerBound].dropFirst(5).utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 || $0 == 95
              }),
              let raw = headers["location"], raw.utf8.count <= 512 else {
            throw ValidationError.malformed
        }
        let url: URL
        do {
            url = try NativeDLNA.rendererURL(raw)
            let sender = try NativeDLNA.rendererURL("http://\(senderIPv4):1900/ssdp")
            guard url.host == sender.host else { throw ValidationError.unsafeLocation }
        } catch { throw ValidationError.unsafeLocation }
        return Candidate(location: url, serviceType: st, uniqueServiceName: usn)
    }
}
