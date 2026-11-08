import XCTest
@testable import TVNext

final class NativeSubtitlePreferencePolicyTests: XCTestCase {
    func testNonMeaningfulTrackIdentityIsRejected() {
        for name in ["", " ", "\t\n", " \u{3000} ", "\u{200B}", "\u{FEFF}", "\u{2060}", " \u{200B}\u{FEFF} ", "\u{0000}", "\u{0007}\u{001B}", "\u{00AD}", "\u{200C}\u{200D}"] {
            XCTAssertNil(NativeSubtitlePreferencePolicy.normalizedChoice(
                displayName: name, languageTag: "en", isOff: false))
        }
    }

    func testMeaningfulTrackIdentityIsPreservedExactly() {
        let identity = NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: " English ", languageTag: "en-US", isOff: false)
        XCTAssertEqual(identity, NativeSubtitlePreferenceIdentity(
            displayName: " English ", languageTag: "en-US", isOff: false))
        XCTAssertNotNil(NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: "中文 字幕", languageTag: nil, isOff: false))
    }

    func testExplicitOffRequiresNoTrackIdentity() {
        XCTAssertEqual(NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: nil, languageTag: nil, isOff: true),
            NativeSubtitlePreferenceIdentity(displayName: nil, languageTag: nil, isOff: true))
        XCTAssertNil(NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: " ", languageTag: nil, isOff: true))
    }
}
