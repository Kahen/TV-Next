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

        precondition(!fm.fileExists(atPath: root.appendingPathComponent("copied.srt").path))
        print("Coordinated Files subtitle bounds, supported formats, invalid encoding and cancellation passed")
    }
}
