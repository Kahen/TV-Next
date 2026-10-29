import Foundation
import XCTest
@testable import TVNext

final class NativeOfflineMediaTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("offline-test-" + UUID().uuidString)
    }

    func testAtomicCatalogRestoresCopiesWithoutSourceURLsAndRejectsTamperedFiles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try NativeOfflineMediaCatalog(directory: root, maxFileBytes: 8, maxTotalBytes: 12, maxEntries: 2)
        let id = UUID()
        try Data([1, 2, 3, 4]).write(to: catalog.stagingURL(id))
        let entry = try catalog.commit(id: id, name: "Owned", fileExtension: "mp4")
        XCTAssertEqual(entry.bytes, 4)
        let file = try XCTUnwrap(catalog.fileURL(entry))
        let restored = try NativeOfflineMediaCatalog(directory: root)
        XCTAssertEqual(restored.entries, [entry])
        XCTAssertEqual(restored.fileURL(entry), file)
        let manifest = try String(contentsOf: root.appendingPathComponent("catalog.json"), encoding: .utf8)
        XCTAssertFalse(manifest.contains("http"))
        XCTAssertFalse(manifest.contains("Authorization"))
        try Data([1]).write(to: file)
        XCTAssertNil(restored.fileURL(entry))
        XCTAssertTrue(try NativeOfflineMediaCatalog(directory: root).entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFileCountByteQuotaRemovalAndOrphanRecovery() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try NativeOfflineMediaCatalog(directory: root, maxFileBytes: 4, maxTotalBytes: 6, maxEntries: 2)
        let firstID = UUID()
        try Data([0, 1, 2, 3]).write(to: catalog.stagingURL(firstID))
        let first = try catalog.commit(id: firstID, name: "One", fileExtension: "mp4")
        let secondID = UUID()
        try Data([0, 1, 2]).write(to: catalog.stagingURL(secondID))
        XCTAssertThrowsError(try catalog.commit(id: secondID, name: "Two", fileExtension: "mp4"))
        XCTAssertEqual(catalog.entries, [first])
        XCTAssertThrowsError(try catalog.commit(id: secondID, name: "Two", fileExtension: "../mp4"))
        try catalog.remove(first)
        XCTAssertNil(catalog.fileURL(first))
        XCTAssertEqual(catalog.usedBytes, 0)
        let restored = try NativeOfflineMediaCatalog(directory: root)
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: catalog.stagingURL(secondID).path))
    }

    func testSourcesExcludeHLSLiveUserinfoFragmentsAndUnsupportedSchemes() {
        XCTAssertNotNil(NativeOfflineMediaCatalog.sourceURL("https://example.test/Owned.MP4?signature=private"))
        for raw in ["file:///tmp/owned.mp4", "https://u:p@example.test/a.mp4", "https://example.test/live.m3u8",
                    "https://example.test/a.mp4#fragment", "https://example.test/a.mp4\n", "https://example.test/a\\b.mp4"] {
            XCTAssertNil(NativeOfflineMediaCatalog.sourceURL(raw), raw)
        }
        XCTAssertTrue(NativeOfflineTransfer.validHeader(Data([0, 0, 0, 24] + Array("ftypisom".utf8)), fileExtension: "mp4"))
        XCTAssertTrue(NativeOfflineTransfer.validHeader(Data("ID3tag".utf8), fileExtension: "mp3"))
        for text in ["#EXTM3U\nhttps://example.test/child.m3u8", "<html>login</html>", "error"] {
            XCTAssertFalse(NativeOfflineTransfer.validHeader(Data(text.utf8), fileExtension: "mp4"))
        }
    }

    func testOwnedHTTPDownloadIsPersistentAndQuotaFailureLeavesNoCopy() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try NativeOfflineMediaCatalog(directory: root)
        let source = URL(string: "http://127.0.0.1:8765/fixture.mp4")!
        let id = UUID()
        try await NativeOfflineTransfer.download(source, to: catalog.stagingURL(id), maxBytes: 1_048_576)
        let entry = try catalog.commit(id: id, name: "Owned", fileExtension: "mp4")
        XCTAssertTrue(try XCTUnwrap(catalog.fileURL(entry)).isFileURL)
        let oversized = catalog.stagingURL(UUID())
        do {
            try await NativeOfflineTransfer.download(source, to: oversized, maxBytes: 1)
            XCTFail("Accepted oversized offline media")
        } catch { XCTAssertFalse(FileManager.default.fileExists(atPath: oversized.path)) }
        let cancelled = catalog.stagingURL(UUID())
        let task = Task {
            try await NativeOfflineTransfer.download(source, to: cancelled, maxBytes: 1_048_576)
        }
        task.cancel()
        do { try await task.value; XCTFail("Cancelled transfer succeeded") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.path))
    }
}
