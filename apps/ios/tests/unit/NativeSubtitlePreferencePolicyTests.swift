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

    func testEncodedIdentityBoundsRejectCombiningSequenceAmplification() {
        let oversizedName = "A" + String(repeating: "\u{0301}", count: 200)
        XCTAssertLessThanOrEqual(oversizedName.count, 80)
        XCTAssertNil(NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: oversizedName, languageTag: "en", isOff: false))
        let oversizedTag = "en" + String(repeating: "\u{0301}", count: 100)
        XCTAssertLessThanOrEqual(oversizedTag.count, 64)
        XCTAssertNil(NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: "English", languageTag: oversizedTag, isOff: false))
        XCTAssertNotNil(NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: String(repeating: "中", count: 80),
            languageTag: "zh-Hans", isOff: false))
    }

    func testExplicitOffRequiresNoTrackIdentity() {
        XCTAssertEqual(NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: nil, languageTag: nil, isOff: true),
            NativeSubtitlePreferenceIdentity(displayName: nil, languageTag: nil, isOff: true))
        XCTAssertNil(NativeSubtitlePreferencePolicy.normalizedChoice(
            displayName: " ", languageTag: nil, isOff: true))
    }
}
