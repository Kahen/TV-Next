import Foundation

/// Bounded, user-initiated subset of FongMi type-4 action JSON.
/// `web` is never automatically opened. Cookie polling and embedded WebViews
/// are deliberately unsupported: no browser credentials are read or forwarded.
struct NativeSubscriptionAction: Decodable {
    struct Web: Decodable {
        struct Cookie: Decodable {
            let url: String?
            let keys: [String]?
        }
        let url: String
        let mode: String?
        let cookie: [Cookie]?

        var externalURL: URL? {
            guard url.utf8.count <= 4096, !url.isEmpty else { return nil }
            let lower = url.lowercased()
            guard lower.hasPrefix("https://") || lower.hasPrefix("http://") else { return nil }
            guard !url.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 || $0.value == 92 }),
                  let parsed = URLComponents(string: url),
                  let scheme = parsed.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  let host = parsed.host, !host.isEmpty,
                  parsed.user == nil, parsed.password == nil,
                  mode == nil || mode == "browser" || mode == "view" else { return nil }
            return parsed.url
        }

        var limitedBrowserFeatures: Bool { mode == "view" || cookie != nil }
    }

    let msg: String?
    let web: Web?

    var message: String? {
        guard let trimmed = msg?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(512))
    }
    var link: URL? { web?.externalURL }
    var unsupported: Bool { (web == nil && message == nil) || (web != nil && link == nil) }
    var limitedBrowserFeatures: Bool { link != nil && (web?.limitedBrowserFeatures ?? false) }
}
