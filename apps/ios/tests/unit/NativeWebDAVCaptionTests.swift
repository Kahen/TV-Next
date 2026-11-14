import Foundation
import XCTest
@testable import TVNext

final class NativeWebDAVCaptionTests: XCTestCase {
    func testCaptionRequestUsesOnlyTheActiveHTTPSConnection() throws {
        let connection = try NativeWebDAVConnection(address: "https://owned.example/dav", username: "alice", password: "pw")
        let item = NativeWebDAVItem(url: connection.root.appendingPathComponent("中文.SRT"), name: "中文.SRT", isDirectory: false)
        let request = try NativeWebDAVCaptionReader.request(for: item, connection: connection)
        XCTAssertEqual(request.url, item.url)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic YWxpY2U6cHc=")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Depth"))
        for url in ["https://foreign.example/dav/a.srt", "https://owned.example/dav2/a.srt",
                    "http://owned.example/dav/a.srt", "https://owned.example/dav/a.srt?token=other",
                    "https://owned.example/dav/%2e%2e/a.srt"] {
            XCTAssertThrowsError(try NativeWebDAVCaptionReader.request(for:
                NativeWebDAVItem(url: URL(string: url)!, name: "a.srt", isDirectory: false), connection: connection))
        }
    }

    func testCaptionPreflightRejectsFoldersFormatsAndOversizedMetadata() throws {
        let connection = try NativeWebDAVConnection(address: "http://owned.example/dav", username: "", password: "")
        func item(_ ext: String, directory: Bool = false, size: Int64? = nil) -> NativeWebDAVItem {
            NativeWebDAVItem(url: connection.root.appendingPathComponent("file." + ext), name: "file." + ext,
                             isDirectory: directory, sizeBytes: size)
        }
        for ext in ["srt", "VTT", "ass", "ssa"] {
            XCTAssertTrue(NativeWebDAVCaptionReader.supported(item(ext)))
            XCTAssertNil(try NativeWebDAVCaptionReader.request(for: item(ext), connection: connection)
                .value(forHTTPHeaderField: "Authorization"))
        }
        for rejected in [item("srt", directory: true), item("mp4"), item("zip"), item("srt", size: 1_048_577)] {
            XCTAssertThrowsError(try NativeWebDAVCaptionReader.request(for: rejected, connection: connection))
        }
        XCTAssertNoThrow(try NativeWebDAVCaptionReader.request(for: item("srt", size: 1_048_576), connection: connection))
        XCTAssertThrowsError(try NativeWebDAVConnection(address: "http://owned.example/dav", username: "alice", password: "pw"))
        XCTAssertNil(NativeWebDAV.responseError(statusCode: 200, expectedLength: -1, expectedStatus: 200))
        XCTAssertNotNil(NativeWebDAV.responseError(statusCode: 207, expectedLength: -1, expectedStatus: 200))
        XCTAssertNotNil(NativeWebDAV.responseError(statusCode: 206, expectedLength: 100, expectedStatus: 200))
    }
}
