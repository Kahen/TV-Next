import Foundation
import XCTest
@testable import TVNext

final class NativeWebDAVTests: XCTestCase {
    func testSafeDepthOneListingRejectsForeignAndTraversalHrefs() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        let folder = root.appendingPathComponent("Media", isDirectory: true)
        let xml = """
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/Media/</d:href></d:response>
          <d:response><d:href>/dav/Media/Season%201/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/Media/Owned.mp4</d:href></d:response>
          <d:response><d:href>https://foreign.test/dav/Media/evil.mp4</d:href></d:response>
          <d:response><d:href>/dav/Media/%2e%2e/escape.mp4</d:href></d:response>
          <d:response><d:href>/dav/Media/bad%2Fpath.mp4</d:href></d:response>
          <d:response><d:href>/dav/Media/nested/too-deep.mp4</d:href></d:response>
        </d:multistatus>
        """
        let entries = try NativeWebDAV.parse(Data(xml.utf8), root: root, folder: folder)
        XCTAssertEqual(entries.map(\.name), ["Season 1", "Owned.mp4"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertFalse(entries[1].isDirectory)
        XCTAssertTrue(NativeWebDAV.playable(entries[1]))
        XCTAssertFalse(NativeWebDAV.playable(entries[0]))
    }

    func testCredentialPolicyAndInvalidResponses() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        XCTAssertEqual(try NativeWebDAV.authorization(username: "alice", password: "pw", root: root), "Basic YWxpY2U6cHc=")
        XCTAssertNil(try NativeWebDAV.authorization(username: "", password: "", root: root))
        XCTAssertThrowsError(try NativeWebDAV.rootURL("http://example.test/dav", username: "alice", password: "pw"))
        XCTAssertThrowsError(try NativeWebDAV.rootURL("https://alice:pw@example.test/dav"))
        XCTAssertThrowsError(try NativeWebDAV.rootURL("https://example.test/dav?token=secret"))
        XCTAssertThrowsError(try NativeWebDAV.rootURL("https://example.test/dav/%252e%252e"))
        XCTAssertThrowsError(try NativeWebDAV.parse(Data("<!DOCTYPE x><d:multistatus xmlns:d=\"DAV:\"/>".utf8), root: root, folder: root))
        XCTAssertThrowsError(try NativeWebDAV.parse(Data(repeating: 65, count: 1_048_577), root: root, folder: root))
    }
}
