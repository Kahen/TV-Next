import Foundation
import XCTest
@testable import TVNext

@MainActor
final class NativeRemoteCaptionTests: XCTestCase {
    private let srt = "1\n00:00:01,000 --> 00:00:03,000\nOwned captions\n"

    func testNewerSubtitleChoiceWinsEvenIfCancelledFetchReturnsLast() async {
        var pending: [String: CheckedContinuation<String, Error>] = [:]
        let oldStarted = expectation(description: "Old request started")
        let newStarted = expectation(description: "New request started")
        let loader = NativeRemoteCaptionLoader { _, url in
            try await withCheckedThrowingContinuation { continuation in
                pending[url] = continuation
                if url == "old" { oldStarted.fulfill() } else { newStarted.fulfill() }
            }
        }
        let api = TVNextAPI(server: URL(string: "https://api.example")!)
        var applied: [String] = []
        let first = loader.load(NativePlaybackResource(name: "Old", url: "old"), api: api,
                                isCurrent: { true }) { _, name in applied.append(name) }
        // Start the first fetch before selecting its replacement.
        await fulfillment(of: [oldStarted], timeout: 3)
        let second = loader.load(NativePlaybackResource(name: "New", url: "new"), api: api,
                                 isCurrent: { true }) { cues, name in
            XCTAssertEqual(cues.first?.text, "Owned captions")
            applied.append(name)
        }
        await fulfillment(of: [newStarted], timeout: 3)
        pending["new"]?.resume(returning: srt)
        await second.value
        pending["old"]?.resume(returning: srt)
        await first.value
        XCTAssertEqual(applied, ["New"])
        XCTAssertFalse(loader.busy)
        XCTAssertNil(loader.error)
    }

    func testMediaChangeAndInvalidSubtitlesDoNotReplaceExistingCues() async {
        let api = TVNextAPI(server: URL(string: "https://api.example")!)
        var applied = false
        let invalid = NativeRemoteCaptionLoader { _, _ in "<html>not captions</html>" }
        await invalid.load(NativePlaybackResource(name: "Invalid", url: "ignored"), api: api,
                           isCurrent: { true }) { _, _ in applied = true }.value
        XCTAssertFalse(applied)
        XCTAssertNotNil(invalid.error)
        let stale = NativeRemoteCaptionLoader { [srt] _, _ in srt }
        await stale.load(NativePlaybackResource(name: "Stale", url: "ignored"), api: api,
                         isCurrent: { false }) { _, _ in applied = true }.value
        XCTAssertFalse(applied)
        XCTAssertFalse(stale.busy)
        XCTAssertNil(stale.error)
    }
}
