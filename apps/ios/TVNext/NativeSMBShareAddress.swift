import Foundation

/// A credential-free SMB location for the future native share browser.
/// Parsing is deliberately separate from network access: no connection or
/// authentication is attempted for a user-supplied address.
struct NativeSMBShareAddress: Equatable {
    let host: String
    let port: Int
    let share: String
    let components: [String]

    static func parse(_ input: String) -> NativeSMBShareAddress? {
        guard input.utf8.count <= 2048,
              let url = URLComponents(string: input),
              url.scheme?.lowercased() == "smb",
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              let host = url.host, !host.isEmpty,
              host.utf8.count <= 253,
              !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }),
              let port = url.port.map({ $0 }) ?? 445 as Int?,
              (1...65535).contains(port) else { return nil }

        let raw = url.percentEncodedPath
        guard raw.hasPrefix("/"), !raw.hasPrefix("//") else { return nil }
        let pieces = raw.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 65 else { return nil }
        var decoded: [String] = []
        for piece in pieces {
            guard !piece.isEmpty,
                  let value = String(piece).removingPercentEncoding,
                  !value.isEmpty, value != ".", value != "..",
                  value.utf8.count <= 255,
                  !value.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0) ||
                      $0.properties.generalCategory == .format ||
                      $0.value == 0x2028 || $0.value == 0x2029
                  }),
                  !value.contains("/"), !value.contains("\\"),
                  !value.contains("%") else { return nil }
            decoded.append(value)
        }
        guard let share = decoded.first else { return nil }
        return NativeSMBShareAddress(host: host, port: port, share: share, components: Array(decoded.dropFirst()))
    }
}
