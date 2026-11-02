import Foundation

/// A stored track identity may be restored only if it identifies exactly one
/// AVFoundation option across the *entire* group. The UI exposes 16 entries,
/// but hidden later options must still participate in ambiguity checks.
enum NativeTrackPreferencePolicy {
    static let maxVisibleOptions = 16

    static func uniqueVisibleIndex(
        in options: [(name: String, languageTag: String?)],
        name: String,
        languageTag: String?
    ) -> Int? {
        guard !name.isEmpty, name.count <= 80, (languageTag?.count ?? 0) <= 64 else { return nil }
        var match: Int?
        for (index, option) in options.enumerated() where option.name == name && option.languageTag == languageTag {
            // A second matching option, even beyond the 16-item menu, makes
            // the saved preference ambiguous. Do not select either rendition.
            guard match == nil else { return nil }
            match = index
        }
        guard let match, match < maxVisibleOptions else { return nil }
        return match
    }
}
