import Foundation

@main struct SubtitlePreferenceSmoke {
    static func main() {
        let accepted = NativeSubtitlePreferencePolicy.normalizedChoice(displayName: "中文", languageTag: "zh-Hans", isOff: false)
        precondition(accepted == NativeSubtitlePreferenceIdentity(displayName: "中文", languageTag: "zh-Hans", isOff: false))
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: String(repeating: "x", count: 80), languageTag: String(repeating: "z", count: 64), isOff: false) != nil)
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: String(repeating: "x", count: 81), languageTag: "en", isOff: false) == nil)
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: "English", languageTag: String(repeating: "z", count: 65), isOff: false) == nil)
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: "", languageTag: nil, isOff: false) == nil)
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: " \t\n ", languageTag: "en", isOff: false) == nil)
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: "\u{200B}\u{FEFF}\u{2060}", languageTag: nil, isOff: false) == nil, "invisible-only track must be rejected")
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: "\u{0000}\u{0007}", languageTag: nil, isOff: false) == nil, "control-only track must be rejected")
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: "\u{00AD}\u{200C}\u{200D}", languageTag: nil, isOff: false) == nil, "format-only track must be rejected")
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: "中文 字幕", languageTag: "zh", isOff: false) != nil)
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: " English ", languageTag: nil, isOff: false)?.displayName == " English ")
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: nil, languageTag: nil, isOff: false) == nil)
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: nil, languageTag: nil, isOff: true) == NativeSubtitlePreferenceIdentity(displayName: nil, languageTag: nil, isOff: true))
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: "English", languageTag: nil, isOff: true) == nil)
        precondition(NativeSubtitlePreferencePolicy.normalizedChoice(displayName: nil, languageTag: "en", isOff: true) == nil)
        print("Subtitle preference identity: valid/off/invalid/boundary cases passed")
    }
}
