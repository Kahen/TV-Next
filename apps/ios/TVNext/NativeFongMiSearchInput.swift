import Foundation

/// Bounded user-entered search text. Does not alter meaningful Unicode or internal spaces.
enum NativeFongMiSearchInput {
    static let maximumCharacters = 256

    static func validated(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumCharacters else { return nil }
        // Reject invisible control/format characters that can split or spoof queries.
        guard !value.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control ||
            $0.properties.generalCategory == .format ||
            $0.value == 0x2028 || $0.value == 0x2029
        }) else { return nil }
        return value
    }
}
