import Foundation

/// An explicit, short-lived retry target for a FongMi browser action.
/// Only an action identity is retained; browser cookies and credentials are not read.
struct NativeActionRetryContext {
    let siteKey: String
    let action: String
    let subscriptionContent: String
    let subscriptionURL: String

    init?(siteKey: String, action: String, subscriptionContent: String, subscriptionURL: String) {
        guard !siteKey.isEmpty, !action.isEmpty,
              siteKey.utf8.count <= 256, action.utf8.count <= 4096,
              !siteKey.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !action.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        self.siteKey = siteKey
        self.action = action
        self.subscriptionContent = subscriptionContent
        self.subscriptionURL = subscriptionURL
    }

    func matches(siteKey: String, subscriptionContent: String, subscriptionURL: String) -> Bool {
        self.siteKey == siteKey &&
        self.subscriptionContent == subscriptionContent &&
        self.subscriptionURL == subscriptionURL
    }
}
