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

        let vtt = """
        WEBVTT

        00:00:02.000 --> 00:00:05.000 align:start
        VTT caption
        """
        let vttCues = try CaptionParser.parse(Data(vtt.utf8))
        precondition(vttCues.count == 1 && vttCues[0].text == "VTT caption")

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

        print("TV-Next caption parser smoke tests passed")
    }
}
