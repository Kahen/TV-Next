import AVFoundation
import Foundation
import XCTest
@testable import TVNext

@MainActor
final class NativePlaybackDiagnosticsTests: XCTestCase {
    func testOwnedMP4ReportsActualCodecAndDimensions() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixture", withExtension: "mp4"))
        let metadata = try await NativeMediaMetadata.collect(AVURLAsset(url: url))
        XCTAssertTrue(metadata.video.contains { $0.contains("H.264") && $0.contains("160×90") }, "Unexpected metadata: \(metadata)")
        XCTAssertFalse(String(describing: metadata).contains("file://"))
    }

    func testDiagnosticErrorsCannotExposeSignedURLsOrServerDetails() {
        let privateURL = "https://private.example/movie?token=secret"
        let error = NSError(domain: privateURL, code: -42, userInfo: [NSLocalizedDescriptionKey: privateURL,
            NSURLErrorFailingURLErrorKey: URL(string: privateURL)!])
        XCTAssertEqual(NativePlaybackTimeline.errorCode(error), "PlayerError (-42)")
        XCTAssertEqual(NativePlaybackTimeline.errorCode(NSError(domain: NSURLErrorDomain, code: -1009)), "NSURLErrorDomain (-1009)")
        XCTAssertNil(NativePlaybackTimeline.errorCode(nil))
        XCTAssertFalse(NativePlaybackTimeline.seconds(.nan).contains("nan"))
        XCTAssertFalse(NativePlaybackTimeline.seconds(.infinity).contains("inf"))
        XCTAssertEqual(NativeMediaMetadata.codec(0x61766331), "H.264 (avc1)")
        XCTAssertEqual(NativeMediaMetadata.codec(0x00000000), "0x00000000")
    }

    func testOwnedPCMAudioReportsSampleRateAndChannelCount() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for index in 0..<2 { channels[index].initialize(repeating: 0, count: 4800) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let metadata = try await NativeMediaMetadata.collect(AVURLAsset(url: url))
        XCTAssertTrue(metadata.video.isEmpty)
        XCTAssertTrue(metadata.audio.contains { $0.contains("48000 Hz") && $0.contains("2 声道") })
    }

    func testEmptyPlayerHasNoStaleTimelineOrError() {
        let value = NativePlaybackTimeline.capture(AVPlayer())
        XCTAssertEqual(value.state, "尚未选择媒体")
        XCTAssertEqual(value.position, "—")
        XCTAssertNil(value.error)
    }
}
