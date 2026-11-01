import Foundation
import XCTest
@testable import TVNext

final class LocalCaptionReaderTests: XCTestCase {
    private func withFolder(_ work: (URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await work(folder)
    }

    func testSupportedSRTAndWebVTTReadWithBoundedContent() async throws {
        try await withFolder { root in
            let srt = root.appendingPathComponent("caption.SRT")
            try Data("1\n00:00:01,000 --> 00:00:02,500\nOwned\n".utf8).write(to: srt)
            let cues = try await LocalCaptionReader.load(srt)
            XCTAssertEqual(cues.count, 1)
            XCTAssertEqual(cues.first?.text, "Owned")
            XCTAssertEqual(cues.first?.end, 2.5)

            let vtt = root.appendingPathComponent("caption.vtt")
            try Data("WEBVTT\n\n00:00:03.000 --> 00:00:04.000\nProvider\n".utf8).write(to: vtt)
            let vttCues = try await LocalCaptionReader.load(vtt)
            XCTAssertEqual(vttCues, [CaptionCue(start: 3, end: 4, text: "Provider")])
        }
    }

    func testBOMMarkedUTF16FileProviderSubtitle() async throws {
        try await withFolder { root in
            let source = root.appendingPathComponent("subtitle.srt")
            let text = "1\n00:00:01,000 --> 00:00:03,000\nNAS 中文字幕\n"
            var bytes = Data([0xFF, 0xFE])
            bytes.append(try XCTUnwrap(text.data(using: .utf16LittleEndian)))
            try bytes.write(to: source)
            let cues = try await LocalCaptionReader.load(source)
            XCTAssertEqual(cues, [CaptionCue(start: 1, end: 3, text: "NAS 中文字幕")])
        }
    }

    func testEmptyOversizedAndUnsupportedFilesFailClosed() async throws {
        try await withFolder { root in
            let empty = root.appendingPathComponent("empty.srt")
            try Data().write(to: empty)
            do {
                _ = try await LocalCaptionReader.load(empty)
                XCTFail("Empty caption was accepted")
            } catch CaptionError.empty {}

            let huge = root.appendingPathComponent("huge.ass")
            try Data([1]).write(to: huge)
            let handle = try FileHandle(forWritingTo: huge)
            try handle.truncate(atOffset: UInt64(LocalCaptionReader.maxBytes + 1))
            try handle.close()
            do {
                _ = try await LocalCaptionReader.load(huge)
                XCTFail("Oversized caption was accepted")
            } catch CaptionError.tooLarge {}

            let executable = root.appendingPathComponent("caption.js")
            try Data("WEBVTT".utf8).write(to: executable)
            do {
                _ = try await LocalCaptionReader.load(executable)
                XCTFail("Executable extension was accepted")
            } catch CaptionError.invalidTimeline {}

            let directory = root.appendingPathComponent("folder.vtt", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            do {
                _ = try await LocalCaptionReader.load(directory)
                XCTFail("Directory was accepted")
            } catch CaptionError.invalidTimeline {}
        }
    }

    func testOnlyActualPickerCancellationIsSilent() {
        XCTAssertTrue(LocalCaptionReader.isUserCancellation(CocoaError(.userCancelled)))
        XCTAssertTrue(LocalCaptionReader.isUserCancellation(CancellationError()))
        XCTAssertFalse(LocalCaptionReader.isUserCancellation(CocoaError(.fileReadNoPermission)))
        XCTAssertFalse(LocalCaptionReader.isUserCancellation(URLError(.notConnectedToInternet)))
    }

    func testInvalidEncodingAndPreCancellationDoNotProduceCues() async throws {
        try await withFolder { root in
            let invalid = root.appendingPathComponent("bad.ssa")
            try Data([0xFF, 0xFE]).write(to: invalid)
            do {
                _ = try await LocalCaptionReader.load(invalid)
                XCTFail("Invalid UTF-8 was accepted")
            } catch CaptionError.invalidEncoding {}

            let valid = root.appendingPathComponent("valid.srt")
            try Data("1\n00:00:00,000 --> 00:00:01,000\nOK\n".utf8).write(to: valid)
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await LocalCaptionReader.load(valid)
            }
            do {
                _ = try await cancelled.value
                XCTFail("Cancelled load completed")
            } catch is CancellationError {}
        }
    }
}
