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
          <d:response><d:href>/dav/Media/Season%201</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
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
        XCTAssertTrue(entries[0].url.absoluteString.hasSuffix("/"), "Directory hrefs must be canonicalized for nested PROPFIND")
        XCTAssertFalse(entries[1].isDirectory)
        XCTAssertTrue(NativeWebDAV.playable(entries[1]))
        XCTAssertFalse(NativeWebDAV.playable(entries[0]))
    }

    func testSuccessfulPropstatAndDirectDAVHrefOnly() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        let folder = root.appendingPathComponent("Movies", isDirectory: true)

        let mixed = """
        <d:multistatus xmlns:d="DAV:" xmlns:x="urn:foreign">
          <d:response>
            <d:href>/dav/Movies/Good.mp4</d:href>
            <d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Movies/Folder/</d:href>
            <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
            <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Movies/NotFound.mp4</d:href>
            <d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Movies/Spoofed.mp4</d:href>
            <d:propstat><d:prop><d:resourcetype><x:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
            <x:href>/dav/Movies/Wrong.mp4</x:href>
            <d:propstat><d:prop><x:resourcetype><d:collection/></x:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Movies/Nested.mp4</d:href>
            <d:propstat><d:prop><d:href>/dav/Movies/Injected.mp4</d:href><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Movies/Failed.mp4</d:href>
            <d:status>HTTP/1.1 404 Not Found</d:status>
            <d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Movies/BadStatus.mp4</d:href>
            <d:propstat><d:prop><d:resourcetype/></d:prop><d:status>garbage</d:status></d:propstat>
          </d:response>
        </d:multistatus>
        """
        let entries = try NativeWebDAV.parse(Data(mixed.utf8), root: root, folder: folder)
        XCTAssertEqual(entries.map(\\.name), ["Folder", "Good.mp4", "Nested.mp4", "Spoofed.mp4"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertTrue(entries.dropFirst().allSatisfy { !$0.isDirectory })
    }

    func testCredentialPolicyAndInvalidResponses() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        XCTAssertEqual(try NativeWebDAV.authorization(username: "alice", password: "pw", root: root), "Basic YWxpY2U6cHc=")
        XCTAssertNil(try NativeWebDAV.authorization(username: "", password: "", root: root))
        XCTAssertThrowsError(try NativeWebDAV.rootURL("http://example.test/dav", username: "alice", password: "pw"))
        XCTAssertThrowsError(try NativeWebDAV.rootURL("https://alice:pw@example.test/dav"))
        XCTAssertThrowsError(try NativeWebDAV.rootURL("https://example.test/dav?token=secret"))
        XCTAssertThrowsError(try NativeWebDAV.rootURL("https://example.test/dav/%252e%252e"))
        XCTAssertThrowsError(try NativeWebDAV.authorization(username: String(repeating: "x", count: 257), password: "pw", root: root))
        XCTAssertThrowsError(try NativeWebDAV.parse(Data("<!DOCTYPE x><d:multistatus xmlns:d=\"DAV:\"/>".utf8), root: root, folder: root))
        XCTAssertThrowsError(try NativeWebDAV.parse(Data(repeating: 65, count: 1_048_577), root: root, folder: root))
    }
}
