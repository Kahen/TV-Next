import Foundation

@main
struct CaptionFilesSmoke {
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let sample = Data("1\n00:00:01,000 --> 00:00:03,000\nSMB subtitle\n".utf8)
        let valid = root.appendingPathComponent("owned.SRT")
        try sample.write(to: valid)
        let cues = try await LocalCaptionReader.load(valid)
        precondition(cues.count == 1 && cues[0].text == "SMB subtitle")
        precondition(cues[0].start == 1 && cues[0].end == 3)

        let utf16 = root.appendingPathComponent("owned-utf16.ssa")
        let ass = "[Events]\nFormat: Start, End, Text\nDialogue: 0:00:01.00,0:00:03.00,中文文件\n"
        var utf16Bytes = Data([0xFE, 0xFF])
        utf16Bytes.append(ass.data(using: .utf16BigEndian)!)
        try utf16Bytes.write(to: utf16)
        let utf16Cues = try await LocalCaptionReader.load(utf16)
        precondition(utf16Cues.count == 1 && utf16Cues[0].text == "中文文件")

        let legacy = root.appendingPathComponent("owned-gb18030.srt")
        try (Data("1\n00:00:01,000 --> 00:00:03,000\n".utf8) +
             Data([0xD6, 0xD0, 0xCE, 0xC4]) + Data("\n".utf8)).write(to: legacy)
        do {
            _ = try await LocalCaptionReader.load(legacy)
            fatalError("Implicit legacy encoding accepted")
        } catch CaptionError.invalidEncoding {}
        let legacyCues = try await LocalCaptionReader.load(legacy, encoding: .gb18030)
        precondition(legacyCues.first?.text == "中文")

        let boundary = root.appendingPathComponent("boundary.vtt")
        let header = Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nVisible\n".utf8)
        var exactly = header
        exactly.append(Data(repeating: 32, count: LocalCaptionReader.maxBytes - header.count))
        try exactly.write(to: boundary)
        let boundaryCues = try await LocalCaptionReader.load(boundary)
        precondition(boundaryCues.count == 1)

        let oversized = root.appendingPathComponent("large.srt")
        try sample.write(to: oversized)
        let writer = try FileHandle(forWritingTo: oversized)
        try writer.truncate(atOffset: UInt64(LocalCaptionReader.maxBytes + 1))
        try writer.close()
        do {
            _ = try await LocalCaptionReader.load(oversized)
            fatalError("Oversized caption accepted")
        } catch CaptionError.tooLarge {}

        let empty = root.appendingPathComponent("empty.ssa")
        try Data().write(to: empty)
        do {
            _ = try await LocalCaptionReader.load(empty)
            fatalError("Empty caption accepted")
        } catch CaptionError.empty {}

        let invalid = root.appendingPathComponent("bad.ass")
        try Data([0xFF, 0xFE]).write(to: invalid)
        do {
            _ = try await LocalCaptionReader.load(invalid)
            fatalError("Invalid UTF-8 accepted")
        } catch CaptionError.invalidEncoding {}

        let unsupported = root.appendingPathComponent("owned.js")
        try sample.write(to: unsupported)
        do {
            _ = try await LocalCaptionReader.load(unsupported)
            fatalError("Unsupported extension accepted")
        } catch CaptionError.invalidTimeline {}

        let directory = root.appendingPathComponent("folder.srt", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            _ = try await LocalCaptionReader.load(directory)
            fatalError("Directory accepted")
        } catch CaptionError.invalidTimeline {}

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LocalCaptionReader.load(valid)
        }
        do {
            _ = try await cancelled.value
            fatalError("Pre-cancelled import accepted")
        } catch is CancellationError {}

        precondition(LocalCaptionReader.isUserCancellation(CocoaError(.userCancelled)))
        precondition(LocalCaptionReader.isUserCancellation(CancellationError()))
        precondition(!LocalCaptionReader.isUserCancellation(CocoaError(.fileReadNoPermission)))
        precondition(!LocalCaptionReader.isUserCancellation(URLError(.notConnectedToInternet)))
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("copied.srt").path))
        print("Coordinated Files subtitle bounds, supported formats, invalid encoding and cancellation passed")
    }
}
