import Foundation
import XCTest
@testable import TVNext

final class NativeWebDAVTests: XCTestCase {
    func testActiveConnectionKeepsOriginalCredentialsWhenFormChanges() throws {
        var draftAddress = "https://first.example/dav"
        var draftUsername = "alice"
        var draftPassword = "first-secret"
        let active = try NativeWebDAVConnection(address: draftAddress, username: draftUsername, password: draftPassword)
        draftAddress = "https://second.example/files"
        draftUsername = "bob"
        draftPassword = "second-secret"
        let next = try NativeWebDAVConnection(address: draftAddress, username: draftUsername, password: draftPassword)
        let media = active.root.appendingPathComponent("Owned.mp4")
        XCTAssertEqual(try active.authorization(for: media), "Basic " + Data("alice:first-secret".utf8).base64EncodedString())
        XCTAssertEqual(try next.authorization(for: next.root), "Basic " + Data("bob:second-secret".utf8).base64EncodedString())
        for outside in ["https://second.example/dav/Owned.mp4", "http://first.example/dav/Owned.mp4",
                        "https://first.example:444/dav/Owned.mp4", "https://first.example/dav2/Owned.mp4",
                        "https://first.example/dav/Owned.mp4?token=secret"] {
            XCTAssertThrowsError(try active.authorization(for: URL(string: outside)!)) { error in
                guard let failure = error as? NativeWebDAVError, case .invalidFolder = failure else {
                    return XCTFail("Expected invalidFolder")
                }
            }
        }
        let anonymous = try NativeWebDAVConnection(address: "http://first.example/dav", username: "", password: "")
        XCTAssertNil(try anonymous.authorization(for: anonymous.root))
    }

    func testCredentialBoundsCountUTF8BytesBeforeConnecting() throws {
        let accepted = try NativeWebDAVConnection(address: "https://example.test/dav",
            username: String(repeating: "é", count: 128), password: String(repeating: "é", count: 512))
        XCTAssertNotNil(try accepted.authorization(for: accepted.root))
        XCTAssertThrowsError(try NativeWebDAVConnection(address: "https://example.test/dav",
            username: String(repeating: "é", count: 129), password: "pw"))
        XCTAssertThrowsError(try NativeWebDAVConnection(address: "https://example.test/dav",
            username: "alice", password: String(repeating: "密", count: 400)))
    }

    func testSafeDepthOneListingRejectsForeignAndTraversalHrefs() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        let folder = root.appendingPathComponent("Media", isDirectory: true)
        let xml = """
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/Media/</d:href></d:response>
          <d:response><d:href>/dav/Media/Season%201</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Media/Owned.mp4</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
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
        XCTAssertEqual(entries[0].url.absoluteString, "https://example.test/dav/Media/Season%201/")
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
        XCTAssertEqual(entries.map(\.name), ["Folder", "Good.mp4", "Nested.mp4", "Spoofed.mp4"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertTrue(entries.dropFirst().allSatisfy { !$0.isDirectory })
    }

    func testFolderFirstNaturalSortIsLocalAndStable() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        func item(_ name: String, folder: Bool = false) -> NativeWebDAVItem {
            NativeWebDAVItem(url: root.appendingPathComponent(name, isDirectory: folder),
                             name: name, isDirectory: folder)
        }
        let unsorted = [item("clip10.mp4"), item("Season10", folder: true),
                        item("notes.txt"), item("clip2.mp4"), item("Season2", folder: true)]
        XCTAssertEqual(NativeWebDAV.visibleEntries(unsorted, search: "", mediaOnly: false).map(\.name),
                       ["Season2", "Season10", "clip2.mp4", "clip10.mp4", "notes.txt"])
        XCTAssertEqual(NativeWebDAV.visibleEntries(unsorted, search: "", mediaOnly: false,
                                                   sortOrder: .descending).map(\.name),
                       ["Season10", "Season2", "notes.txt", "clip10.mp4", "clip2.mp4"])
        XCTAssertEqual(NativeWebDAV.visibleEntries(unsorted, search: " CLIP ", mediaOnly: true,
                                                   sortOrder: .descending).map(\.name),
                       ["clip10.mp4", "clip2.mp4"])
        XCTAssertTrue(NativeWebDAV.visibleEntries(unsorted, search: "notes", mediaOnly: true,
                                                  sortOrder: .descending).isEmpty)
        XCTAssertTrue(NativeWebDAV.visibleEntries([], search: "", mediaOnly: false,
                                                  sortOrder: .descending).isEmpty)
        let aliases = [NativeWebDAVItem(url: root.appendingPathComponent("b.mp4"), name: "Same", isDirectory: false),
                       NativeWebDAVItem(url: root.appendingPathComponent("a.mp4"), name: "Same", isDirectory: false)]
        XCTAssertEqual(NativeWebDAV.visibleEntries(aliases, search: "", mediaOnly: false,
                                                   sortOrder: .descending).map(\.url.lastPathComponent),
                       ["a.mp4", "b.mp4"], "Equal names must not reorder unpredictably")
    }

    func testSuccessfulDAVContentLengthIsBoundedAndScopedToPropstat() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        let folder = root.appendingPathComponent("Movies", isDirectory: true)
        let xml = """
        <d:multistatus xmlns:d="DAV:" xmlns:x="urn:foreign">
          <d:response><d:href>/dav/Movies/Good.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>2048</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Zero.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>0</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Bad.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>-1</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Overflow.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>9223372036854775808</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Failed.mp4</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat><d:propstat><d:prop><d:getcontentlength>1024</d:getcontentlength></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Foreign.mp4</d:href><d:propstat><d:prop><d:resourcetype/><x:getcontentlength>999</x:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Folder/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype><d:getcontentlength>999</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Conflict.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>100</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat><d:propstat><d:prop><d:getcontentlength>200</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Duplicate.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>10</d:getcontentlength><d:getcontentlength>10</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        </d:multistatus>
        """
        let items = try NativeWebDAV.parse(Data(xml.utf8), root: root, folder: folder)
        XCTAssertEqual(items.count, 9)
        XCTAssertEqual(items.first(where: { $0.name == "Good.mp4" })?.sizeBytes, 2048)
        XCTAssertEqual(items.first(where: { $0.name == "Zero.mp4" })?.sizeBytes, 0)
        XCTAssertTrue(items.filter { !["Good.mp4", "Zero.mp4"].contains($0.name) }.allSatisfy { $0.sizeBytes == nil })
        for value in ["-1", "+1", "1.5", "NaN", "9223372036854775808", "8796093022209", ""] {
            XCTAssertNil(NativeWebDAV.contentLength(value))
        }
        XCTAssertEqual(NativeWebDAV.contentLength(" 1048576 "), 1_048_576)
    }

    func testDAVLastModifiedIsStrictAndOnlyFromSuccessfulDirectProperties() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        let folder = root.appendingPathComponent("Movies", isDirectory: true)
        let good = "Mon, 01 Jan 2024 12:34:56 GMT"
        XCTAssertNotNil(NativeWebDAV.httpLastModified(good))
        for bad in ["", "Tue, 01 Jan 2024 12:34:56 GMT", "Mon, 01 Jan 2024 12:34:56 PST",
                    "Mon, 01 Jan 2024 12:34:56 GMT\n", "2024-01-01T12:34:56Z",
                    String(repeating: "X", count: 200)] {
            XCTAssertNil(NativeWebDAV.httpLastModified(bad))
        }
        let xml = """
        <d:multistatus xmlns:d="DAV:" xmlns:x="urn:foreign">
          <d:response><d:href>/dav/Movies/Good.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getlastmodified>Mon, 01 Jan 2024 12:34:56 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Failed.mp4</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat><d:propstat><d:prop><d:getlastmodified>Mon, 01 Jan 2024 12:34:56 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Foreign.mp4</d:href><d:propstat><d:prop><d:resourcetype/><x:getlastmodified>Mon, 01 Jan 2024 12:34:56 GMT</x:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Nested.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getlastmodified><d:span>Mon, 01 Jan 2024 12:34:56 GMT</d:span></d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Duplicate.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getlastmodified>Mon, 01 Jan 2024 12:34:56 GMT</d:getlastmodified><d:getlastmodified>Mon, 01 Jan 2024 12:34:56 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Conflict.mp4</d:href><d:propstat><d:prop><d:resourcetype/><d:getlastmodified>Mon, 01 Jan 2024 12:34:56 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat><d:propstat><d:prop><d:getlastmodified>Tue, 02 Jan 2024 12:34:56 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        </d:multistatus>
        """
        let entries = try NativeWebDAV.parse(Data(xml.utf8), root: root, folder: folder)
        XCTAssertEqual(entries.count, 6)
        XCTAssertEqual(entries.first(where: { $0.name == "Good.mp4" })?.lastModified,
                       NativeWebDAV.httpLastModified(good))
        XCTAssertTrue(entries.filter { $0.name != "Good.mp4" }.allSatisfy { $0.lastModified == nil })
    }

    func testLocalFilenameFilterAndMediaOnlyKeepFoldersNavigable() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        let entries = [
            NativeWebDAVItem(url: root.appendingPathComponent("Season", isDirectory: true), name: "Season", isDirectory: true),
            NativeWebDAVItem(url: root.appendingPathComponent("Owned.MP4"), name: "Owned.MP4", isDirectory: false),
            NativeWebDAVItem(url: root.appendingPathComponent("notes.txt"), name: "notes.txt", isDirectory: false)
        ]
        XCTAssertEqual(NativeWebDAV.visibleEntries(entries, search: "", mediaOnly: false).count, 3)
        XCTAssertEqual(NativeWebDAV.visibleEntries(entries, search: "", mediaOnly: true).map(\.name), ["Season", "Owned.MP4"])
        XCTAssertEqual(NativeWebDAV.visibleEntries(entries, search: " owned ", mediaOnly: true).map(\.name), ["Owned.MP4"])
        XCTAssertEqual(NativeWebDAV.visibleEntries(entries, search: "season", mediaOnly: true).map(\.name), ["Season"])
        XCTAssertEqual(NativeWebDAV.visibleEntries(entries, search: "notes", mediaOnly: false).map(\.name), ["notes.txt"])
        XCTAssertTrue(NativeWebDAV.visibleEntries(entries, search: "notes", mediaOnly: true).isEmpty)
        XCTAssertTrue(NativeWebDAV.visibleEntries(entries, search: "not-found", mediaOnly: false).isEmpty)
    }

    func testBreadcrumbsAreCanonicalRootBoundedAndDepthLimited() throws {
        let root = try NativeWebDAV.rootURL("https://example.test/dav")
        let folder = root.appendingPathComponent("Season 1", isDirectory: true)
        let episode = folder.appendingPathComponent("Episode 2", isDirectory: true)
        XCTAssertEqual(NativeWebDAV.navigationPath(root: root, folder: root), [root])
        XCTAssertEqual(NativeWebDAV.navigationPath(root: root, folder: episode), [root, folder, episode])
        let equivalentRoot = URL(string: "https://EXAMPLE.TEST:443/dav/")!
        let equivalentEpisode = URL(string: "https://EXAMPLE.TEST:443/dav/Season%201/Episode%202/")!
        XCTAssertEqual(NativeWebDAV.navigationPath(root: root, folder: equivalentRoot), [root])
        let normalized = NativeWebDAV.navigationPath(root: root, folder: equivalentEpisode)
        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized.first, root, "Breadcrumb root must use configured canonical URL")
        XCTAssertEqual(normalized.map(\.lastPathComponent), ["dav", "Season 1", "Episode 2"])
        XCTAssertTrue(NativeWebDAV.navigationPath(root: root, folder: URL(string: "https://evil.test/dav/")!).isEmpty)
        XCTAssertTrue(NativeWebDAV.navigationPath(root: root, folder: URL(string: "https://example.test/dav2/")!).isEmpty)
        XCTAssertTrue(NativeWebDAV.navigationPath(root: root, folder: root.appendingPathComponent("file.mp4")).isEmpty)
        var deep = root
        for index in 0..<32 { deep.appendPathComponent("d\(index)", isDirectory: true) }
        XCTAssertEqual(NativeWebDAV.navigationPath(root: root, folder: deep).count, 33)
        deep.appendPathComponent("too-deep", isDirectory: true)
        XCTAssertTrue(NativeWebDAV.navigationPath(root: root, folder: deep).isEmpty)
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
