import Foundation
import SafariServices
import SwiftUI

/// Only explicitly HTTPS action links can open inside the native browser.
/// No bearer tokens, cookies, or API credentials are forwarded by TV-Next.
enum NativeActionBrowserPolicy {
    static func approvedURL(_ url: URL?) -> URL? {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              url.port == nil || (1...65535).contains(url.port!) else { return nil }
        return url
    }
}

struct NativeActionBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

struct NativeActionBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
