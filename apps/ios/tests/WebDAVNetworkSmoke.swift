import Foundation

@main struct WebDAVNetworkSmoke {
    static func main() async throws {
        let root = try NativeWebDAV.rootURL("http://127.0.0.1:8767/dav")
        let entries = try await NativeWebDAV.list(root: root, folder: root, username: "", password: "")
        precondition(entries.map(\.name) == ["Folder", "Owned.mp4"])
        let redirect = root.appendingPathComponent("redirect", isDirectory: true)
        do {
            _ = try await NativeWebDAV.list(root: root, folder: redirect, username: "", password: "")
            fatalError("Followed a cross-origin redirect")
        } catch NativeWebDAVError.httpStatus(302) {
            // The client rejects redirects and reports the original response.
        }
        do {
            _ = try await NativeWebDAV.list(root: root, folder: root, username: "alice", password: "pw")
            fatalError("Sent credentials over HTTP")
        } catch NativeWebDAVError.insecureCredentials { }
        let noLength = root.appendingPathComponent("no-length", isDirectory: true)
        let unannounced = try await NativeWebDAV.list(root: root, folder: noLength, username: "", password: "")
        precondition(unannounced == entries, "Unknown-length valid XML should be accepted")
        for path in ["large-declared", "large-streamed"] {
            let oversized = root.appendingPathComponent(path, isDirectory: true)
            do {
                _ = try await NativeWebDAV.list(root: root, folder: oversized, username: "", password: "")
                fatalError("Accepted oversized WebDAV XML from \(path)")
            } catch NativeWebDAVError.responseTooLarge {
                // The declared and the unknown-length transfer must both stop
                // at the same bound, without parsing or returning partial items.
            }
        }
        // A rejected oversized transfer must not poison the next connection.
        let again = try await NativeWebDAV.list(root: root, folder: root, username: "", password: "")
        precondition(again == entries)
        print("Native WebDAV localhost HTTP integration and streaming cap passed")
    }
}
