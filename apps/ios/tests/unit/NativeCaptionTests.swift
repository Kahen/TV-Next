import Foundation
import XCTest
@testable import TVNext

final class NativeCaptionTests: XCTestCase {
    func testBOMMarkedUTF16BothEndiannessesAndMalformedSurrogates() throws {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\n中文字幕\n"
        for (bom, encoding) in [([UInt8]([0xFF, 0xFE]), String.Encoding.utf16LittleEndian),
                                ([UInt8]([0xFE, 0xFF]), String.Encoding.utf16BigEndian)] {
            var data = Data(bom)
            data.append(try XCTUnwrap(srt.data(using: encoding)))
            XCTAssertEqual(try CaptionParser.parse(data).first?.text, "中文字幕")
        }
        for invalid in [Data([0xFF, 0xFE]), Data([0xFF, 0xFE, 0x31]),
                        Data([0xFF, 0xFE, 0x00, 0xD8]),
                        Data([0xFE, 0xFF, 0xDC, 0x00])] {
            XCTAssertThrowsError(try CaptionParser.parse(invalid)) { error in
                guard case CaptionError.invalidEncoding = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertThrowsError(try CaptionParser.parse(Data([0xD6, 0xD0]))) { error in
            guard case CaptionError.invalidEncoding = error else {
                return XCTFail("Legacy charset should remain unsupported: \(error)")
            }
        }
    }

    func testExplicitGB18030ChineseCaptionsAndMalformedBytes() throws {
        let data = Data("1\n00:00:01,000 --> 00:00:02,000\n".utf8) +
            Data([0xD6, 0xD0, 0xCE, 0xC4]) + Data("\n".utf8)
        XCTAssertThrowsError(try CaptionParser.parse(data))
        XCTAssertEqual(try CaptionParser.parse(data, encoding: .gb18030),
                       [CaptionCue(start: 1, end: 2, text: "中文")])
        for malformed in [Data([0x81]), Data([0xFF]), Data([0xFF, 0xFE, 0x31, 0x00]),
                          Data([0xEF, 0xBB, 0xBF]) + data] {
            XCTAssertThrowsError(try CaptionParser.parse(malformed, encoding: .gb18030)) { error in
                guard case CaptionError.invalidEncoding = error else {
                    return XCTFail("Expected strict legacy decode failure: \(error)")
                }
            }
        }
    }

    func testOverlappingVTTDoesNotDropTheSecondLanguage() throws {
        let text = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        First language

        00:00:02.000 --> 00:00:03.000
        Second language
        """
        let cues = try CaptionParser.parse(Data(text.utf8))
        XCTAssertEqual(CaptionParser.activeText(cues, at: 1), "First language")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 2), "First language\nSecond language")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 3), "First language")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 4), "")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 3.5, offset: 1), "First language\nSecond language")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 1.5, offset: -1), "First language\nSecond language")
    }

    func testOverlappingASSDialogueUsesTheSameBoundedTextOverlay() throws {
        let text = """
        [Events]
        Format: Start, End, Text
        Dialogue: 0:00:01.00,0:00:03.00,First\\Nline
        Dialogue: 0:00:02.00,0:00:04.00,{\\i1}Second, with comma
        """
        let cues = try CaptionParser.parse(Data(text.utf8))
        XCTAssertEqual(CaptionParser.activeText(cues, at: 2.5), "First\nline\nSecond, with comma")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 3), "Second, with comma")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 4), "")
    }

    func testCrowdedAndLongOverlapsCannotGrowTheOverlayWithoutBound() {
        let crowded = (1...100).map { CaptionCue(start: 1, end: 3, text: "Line \($0)") }
        XCTAssertEqual(CaptionParser.activeText(crowded, at: 2), "Line 1\nLine 2\nLine 3\nLine 4")
        let long = [CaptionCue(start: 1, end: 3, text: String(repeating: "甲", count: 1_500)),
                    CaptionCue(start: 1, end: 3, text: String(repeating: "乙", count: 1_500))]
        XCTAssertEqual(CaptionParser.activeText(long, at: 2), String(repeating: "甲", count: 1_500) + "\n" + String(repeating: "乙", count: 499))
    }

    func testSRTOverlapStillHonorsFiniteOffsetValidation() throws {
        let text = """
        1
        00:00:01,000 --> 00:00:04,000
        First

        2
        00:00:02,000 --> 00:00:03,000
        Second
        """
        let cues = try CaptionParser.parse(Data(text.utf8))
        XCTAssertEqual(CaptionParser.activeText(cues, at: 2.5), "First\nSecond")
        XCTAssertEqual(CaptionParser.activeText(cues, at: .nan), "")
        XCTAssertEqual(CaptionParser.activeText(cues, at: .infinity), "")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 2.5, offset: .nan), "")
        XCTAssertEqual(CaptionParser.activeText(cues, at: 2.5, offset: 11), "")
    }
}
