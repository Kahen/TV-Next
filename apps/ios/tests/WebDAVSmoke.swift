import Foundation

@main struct WebDAVSmoke {
    static func main() throws {
        let root = try NativeWebDAV.rootURL("https://media.example/dav")
        precondition(root.absoluteString == "https://media.example/dav/")
        let folder = root.appendingPathComponent("Movies", isDirectory: true)
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/Movies/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Sub/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Owned%20Film.mp4</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
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
        do { _ = try NativeWebDAV.parse(Data(repeating: 65, count: 1_048_577), root: root, folder: folder); fatalError("Accepted oversized XML") }
        catch NativeWebDAVError.responseTooLarge { }
        print("Native WebDAV bounded listing smoke passed")
    }
}
