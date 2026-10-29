import Foundation

@main struct WebDAVSmoke {
    static func main() throws {
        let root = try NativeWebDAV.rootURL("https://media.example/dav")
        precondition(root.absoluteString == "https://media.example/dav/")
        let folder = root.appendingPathComponent("Movies", isDirectory: true)
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/Movies/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Sub/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Owned%20Film.mp4</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>https://evil.example/dav/Movies/attack.mp4</d:href></d:response>
          <d:response><d:href>/dav/MoviesExtra/skip.mp4</d:href></d:response>
          <d:response><d:href>/dav/Movies/%2e%2e/escape.mp4</d:href></d:response>
          <d:response><d:href>/dav/Movies/bad%2Fname.mp4</d:href></d:response>
          <d:response><d:href>/dav/Movies/deeper/child.mp4</d:href></d:response>
        </d:multistatus>
        """
        let items = try NativeWebDAV.parse(Data(xml.utf8), root: root, folder: folder)
        precondition(items.map(\.name) == ["Sub", "Owned Film.mp4"], "Unexpected children: \(items)")
        precondition(!NativeWebDAV.playable(items[0]) && NativeWebDAV.playable(items[1]))
        precondition(NativeWebDAV.contains(folder, root: root))
        precondition(!NativeWebDAV.contains(URL(string: "https://media.example/dav2")!, root: root))
        precondition(!NativeWebDAV.contains(URL(string: "https://evil.example/dav/Movies")!, root: root))
        let authorization = try NativeWebDAV.authorization(username: "a", password: "b", root: root)
        precondition(authorization == "Basic YTpi")
        for address in ["http://user:pass@media.example/dav", "https://media.example/dav?token=x", "https://media.example/dav/%2fetc", "javascript:alert(1)"] {
            do { _ = try NativeWebDAV.rootURL(address); fatalError("Accepted invalid root") } catch NativeWebDAVError.invalidAddress { }
        }
        do { _ = try NativeWebDAV.rootURL("http://media.example/dav", username: "u", password: "p"); fatalError("Allowed insecure Basic auth") }
        catch NativeWebDAVError.insecureCredentials { }
        for invalid in ["<!DOCTYPE foo><d:multistatus xmlns:d=\"DAV:\"/>", "<bad>"] {
            do { _ = try NativeWebDAV.parse(Data(invalid.utf8), root: root, folder: folder); fatalError("Accepted invalid XML") }
            catch NativeWebDAVError.invalidResponse { }
        }
        let minimalXML = Data("<d:multistatus xmlns:d=\"DAV:\"></d:multistatus>".utf8)
        var exactlyAtLimit = minimalXML
        exactlyAtLimit.append(Data(repeating: 32, count: 1_048_576 - minimalXML.count))
        let exactBoundaryItems = try NativeWebDAV.parse(exactlyAtLimit, root: root, folder: folder)
        precondition(exactBoundaryItems.isEmpty, "A valid 1 MiB response must remain supported")
        do { _ = try NativeWebDAV.parse(Data(repeating: 65, count: 1_048_577), root: root, folder: folder); fatalError("Accepted oversized XML") }
        catch NativeWebDAVError.responseTooLarge { }

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
        let verified = try NativeWebDAV.parse(Data(mixed.utf8), root: root, folder: folder)
        precondition(verified.map(\.name) == ["Folder", "Good.mp4", "Nested.mp4", "Spoofed.mp4"], "Incorrect propstat/href scope: \(verified)")
        precondition(verified[0].isDirectory && verified.dropFirst().allSatisfy { !$0.isDirectory })
        // Response status validation must be identical whether URLSession calls
        // didReceive(response:) or exposes the response only at completion.
        precondition(NativeWebDAV.responseError(statusCode: 207, expectedLength: -1) == nil)
        precondition(NativeWebDAV.responseError(statusCode: 207, expectedLength: 1_048_576) == nil)
        guard case .some(.responseTooLarge) = NativeWebDAV.responseError(statusCode: 207, expectedLength: 1_048_577) else {
            fatalError("Accepted an oversized declared PROPFIND response")
        }
        for status in [401, 403] {
            guard case .some(.unauthorized) = NativeWebDAV.responseError(statusCode: status, expectedLength: 0) else {
                fatalError("Lost WebDAV authorization failure for HTTP \\(status)")
            }
        }
        for status in [200, 302, 404, 500] {
            guard case .some(.httpStatus(status)) = NativeWebDAV.responseError(statusCode: status, expectedLength: 0) else {
                fatalError("Lost WebDAV non-207 status \\(status)")
            }
        }
        print("Native WebDAV bounded listing and RFC 4918 status smoke passed")
    }
}
