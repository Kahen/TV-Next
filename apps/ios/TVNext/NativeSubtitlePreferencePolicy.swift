import Foundation

/// Complete AVFoundation identity or an explicit Off choice. An unrepresentable
/// track selection must evict a stale saved preference, never abbreviate it.
struct NativeSubtitlePreferenceIdentity: Equatable {
    let displayName: String?
    let languageTag: String?
    let isOff: Bool
}

enum NativeSubtitlePreferencePolicy {
    static func normalizedChoice(displayName: String?, languageTag: String?, isOff: Bool) -> NativeSubtitlePreferenceIdentity? {
        if isOff {
            guard displayName == nil, languageTag == nil else { return nil }
            return NativeSubtitlePreferenceIdentity(displayName: nil, languageTag: nil, isOff: true)
        }
        guard let displayName, !displayName.isEmpty, displayName.count <= 80,
              (languageTag?.count ?? 0) <= 64 else { return nil }
        return NativeSubtitlePreferenceIdentity(displayName: displayName, languageTag: languageTag, isOff: false)
    }
}
