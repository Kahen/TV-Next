import Foundation

@main struct WebDAVNetworkSmoke {
    static func main() async throws {
        let root = try NativeWebDAV.rootURL("http://127.0.0.1:8767/dav")
        let entries: [NativeWebDAVItem]
        do { entries = try await NativeWebDAV.list(root: root, folder: root, username: "", password: "") }
        catch { fatalError("Initial WebDAV listing failed: \(error)") }
        precondition(entries.map(\.name) == ["Folder", "Owned.mp4"])
        let nested = entries[0].url
        precondition(nested.absoluteString == "http://127.0.0.1:8767/dav/Folder/", "Collection href acquired an extra slash")
        let nestedEntries = try await NativeWebDAV.list(root: root, folder: nested, username: "", password: "")
        precondition(nestedEntries.isEmpty)
        precondition(NativeWebDAV.navigationPath(root: root, folder: nested) == [root, nested])
        // URLSession can complete a rejected redirect without a separate
        // didReceive(response:) callback. Both local and external Location
        // values must consistently surface the original 302, never follow it.
        for path in ["redirect", "redirect-local"] {
            let redirect = root.appendingPathComponent(path, isDirectory: true)
            do {
                _ = try await NativeWebDAV.list(root: root, folder: redirect, username: "", password: "")
                fatalError("Followed a WebDAV redirect: \(path)")
            } catch NativeWebDAVError.httpStatus(302) {
                // Expected: explicit original status, not an ambiguous transport error.
            } catch {
                fatalError("Unexpected redirect result for \(path): \(error)")
            }
        }
        // Non-207 responses must retain their original status even when the
        // response callback is omitted and only URLSessionTask.response exists.
        for (path, status) in [("ok-not-multistatus", 200), ("missing", 404)] {
            do {
                _ = try await NativeWebDAV.list(root: root, folder: root.appendingPathComponent(path, isDirectory: true), username: "", password: "")
                fatalError("Accepted non-207 WebDAV status \(status)")
            } catch NativeWebDAVError.httpStatus(let code) where code == status {
                // Expected.
            } catch {
                fatalError("Unexpected WebDAV status result for \(path): \(error)")
            }
        }
        for path in ["unauthorized", "forbidden"] {
            do {
                _ = try await NativeWebDAV.list(root: root, folder: root.appendingPathComponent(path, isDirectory: true), username: "", password: "")
                fatalError("Accepted unauthorized WebDAV response: \(path)")
            } catch NativeWebDAVError.unauthorized {
                // Expected.
            } catch {
                fatalError("Unexpected WebDAV auth result for \(path): \(error)")
            }
        }
        do {
            _ = try await NativeWebDAV.list(root: root, folder: root.appendingPathComponent("empty-multistatus", isDirectory: true), username: "", password: "")
            fatalError("Accepted empty WebDAV multistatus")
        } catch NativeWebDAVError.invalidResponse {
            // Valid 207 status is not sufficient without valid DAV XML.
        }
        do {
            _ = try await NativeWebDAV.list(root: root, folder: root, username: "alice", password: "pw")
            fatalError("Sent credentials over HTTP")
        } catch NativeWebDAVError.insecureCredentials { }
        let noLength = root.appendingPathComponent("no-length", isDirectory: true)
        let unannounced: [NativeWebDAVItem]
        do { unannounced = try await NativeWebDAV.list(root: root, folder: noLength, username: "", password: "") }
        catch { fatalError("Unknown-length WebDAV listing failed: \(error)") }
        precondition(unannounced.map(\.name) == entries.map(\.name), "Unknown-length valid XML should be accepted")
        for path in ["large-declared", "large-streamed"] {
            let oversized = root.appendingPathComponent(path, isDirectory: true)
            do {
                _ = try await NativeWebDAV.list(root: root, folder: oversized, username: "", password: "")
                fatalError("Accepted oversized WebDAV XML from \(path)")
            } catch NativeWebDAVError.responseTooLarge {
                // The declared and the unknown-length transfer must both stop
                // at the same bound, without parsing or returning partial items.
            } catch {
                fatalError("Unexpected oversized WebDAV response for \(path): \(error)")
            }
        }
        // A rejected oversized transfer must not poison the next connection.
        let again: [NativeWebDAVItem]
        do { again = try await NativeWebDAV.list(root: root, folder: root, username: "", password: "") }
        catch { fatalError("WebDAV listing after rejected oversized transfer failed: \(error)") }
        precondition(again == entries)
        print("Native WebDAV localhost HTTP integration and streaming cap passed")
    }
}
