import Foundation

@main
struct CaptionSmoke {
    static func main() throws {
        let srt = """
        1
        00:00:01,100 --> 00:00:02,250
        Hello <i>world</i>

        2
        00:01:00,500 --> 00:01:02,000
        Second line
        """
        let srtCues = try CaptionParser.parse(Data(srt.utf8))
        precondition(srtCues.count == 2)
        precondition(srtCues[0].start == 1.1 && srtCues[0].end == 2.25)
        precondition(srtCues[0].text == "Hello world")
        precondition(srtCues[1].start == 60.5)

        // Real-world Files/SMB SRT files may be UTF-16LE or UTF-16BE.
        // Both must use an explicit BOM; legacy encoding guessing is forbidden.
        let multilingual = "1\n00:00:01,000 --> 00:00:02,000\n中文 UTF-16\n"
        for (bom, encoding) in [([UInt8]([0xFF, 0xFE]), String.Encoding.utf16LittleEndian),
                                ([UInt8]([0xFE, 0xFF]), String.Encoding.utf16BigEndian)] {
            var bytes = Data(bom)
            bytes.append(multilingual.data(using: encoding)!)
            let cues = try CaptionParser.parse(bytes)
            precondition(cues.count == 1 && cues[0].text == "中文 UTF-16")
        }
        let utf8BOM = Data([0xEF, 0xBB, 0xBF]) + Data(multilingual.utf8)
        let utf8BOMCues = try CaptionParser.parse(utf8BOM)
        precondition(utf8BOMCues.first?.text == "中文 UTF-16")
        for malformed in [Data([0xFF, 0xFE]), Data([0xFF, 0xFE, 0x31]),
                          Data([0xFE, 0xFF, 0xD8, 0x00]),
                          Data([0xFF, 0xFE, 0x00, 0xDC]),
                          Data([0xFF, 0xFE, 0x00, 0xD8, 0x31, 0x00]),
                          Data([0xD6, 0xD0])] {
            do {
                _ = try CaptionParser.parse(malformed)
                fatalError("Malformed or unsupported encoding accepted")
            } catch CaptionError.invalidEncoding {}
        }
        do {
            _ = try CaptionParser.parse(multilingual.data(using: .utf16LittleEndian)!)
            fatalError("BOM-less UTF-16 was accepted")
        } catch CaptionError.invalidEncoding {}

        // Legacy Simplified Chinese bytes are never guessed in Unicode mode.
        let gb18030 = Data("1\n00:00:01,000 --> 00:00:02,000\n".utf8) +
            Data([0xD6, 0xD0, 0xCE, 0xC4]) + Data("\n".utf8)
        do {
            _ = try CaptionParser.parse(gb18030)
            fatalError("Implicit GB18030 fallback accepted")
        } catch CaptionError.invalidEncoding {}
        precondition(try CaptionParser.parse(gb18030, encoding: .gb18030).first?.text == "中文")
        for invalid in [Data([0x81]), Data([0xFF]), Data([0xFF, 0xFE, 0x31, 0x00]), utf8BOM] {
            do {
                _ = try CaptionParser.parse(invalid, encoding: .gb18030)
                fatalError("Malformed or BOM-marked GB18030 input accepted")
            } catch CaptionError.invalidEncoding {}
        }

        let vtt = """
        WEBVTT

        00:00:02.000 --> 00:00:05.000 align:start
        VTT caption
        """
        let vttCues = try CaptionParser.parse(Data(vtt.utf8))
        precondition(vttCues.count == 1 && vttCues[0].text == "VTT caption")

        let ass = """
        [Script Info]
        Title: authorized fixture
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.20,0:00:03.45,Default,,0,0,0,,{\\i1}Hello, <world>\\Nsecond line
        Dialogue: 0,0:60:00.00,0:61:00.00,Default,,0,0,0,,bad
        """
        let assCues = try CaptionParser.parse(Data(ass.utf8))
        precondition(assCues.count == 1)
        precondition(assCues[0].start == 1.2 && assCues[0].end == 3.45)
        precondition(assCues[0].text == "Hello, <world>\nsecond line")
        precondition(CaptionParser.activeText(assCues, at: 2) == "Hello, <world>\nsecond line")
        do {
            _ = try CaptionParser.parse(Data("[Events]\nFormat: Start, End, Text\nDialogue: 0:00:02.00,0:00:01.00,invalid".utf8))
            fatalError("Invalid ASS timing accepted")
        } catch CaptionError.invalidTimeline {}

        do {
            _ = try CaptionParser.parse(Data("bad".utf8))
            fatalError("Malformed captions accepted")
        } catch CaptionError.invalidTimeline {}

        do {
            _ = try CaptionParser.parse(Data(repeating: 65, count: 1_048_577))
            fatalError("Oversized caption accepted")
        } catch CaptionError.tooLarge {}

        // Positive offset delays text; negative offset advances it.
        precondition(CaptionParser.activeText(srtCues, at: 1.5) == "Hello world")
        precondition(CaptionParser.activeText(srtCues, at: 1.5, offset: 1) == "")
        precondition(CaptionParser.activeText(srtCues, at: 2.5, offset: 1) == "Hello world")
        precondition(CaptionParser.activeText(srtCues, at: 0.5, offset: -1) == "Hello world")
        precondition(CaptionParser.activeText(srtCues, at: 2.25) == "")
        precondition(CaptionParser.activeText(srtCues, at: .infinity) == "")
        precondition(CaptionParser.activeText(srtCues, at: 1.5, offset: 11) == "")

        let overlapping = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        First language

        00:00:02.000 --> 00:00:03.000
        Second language
        """
        let overlapCues = try CaptionParser.parse(Data(overlapping.utf8))
        precondition(CaptionParser.activeText(overlapCues, at: 2.5) == "First language\nSecond language")
        precondition(CaptionParser.activeText(overlapCues, at: 3) == "First language")
        precondition(CaptionParser.activeText(overlapCues, at: 4).isEmpty)
        precondition(CaptionParser.activeText(overlapCues, at: 3.5, offset: 1) == "First language\nSecond language")
        precondition(CaptionParser.activeText(overlapCues, at: 1.5, offset: -1) == "First language\nSecond language")
        let crowded = (1...6).map { CaptionCue(start: 1, end: 4, text: "Line \($0)") }
        precondition(CaptionParser.activeText(crowded, at: 2) == "Line 1\nLine 2\nLine 3\nLine 4")
        let long = [CaptionCue(start: 1, end: 4, text: String(repeating: "甲", count: 1_500)),
                    CaptionCue(start: 1, end: 4, text: String(repeating: "乙", count: 1_500))]
        precondition(CaptionParser.activeText(long, at: 2).count == 2_000)

        print("TV-Next caption parser smoke tests passed")
    }
}
