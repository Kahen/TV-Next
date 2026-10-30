import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct NativeWebDAVItem: Identifiable, Equatable {
    let url: URL
    let name: String
    let isDirectory: Bool
    // Optional DAV:getcontentlength metadata, never used to allocate memory.
    var sizeBytes: Int64? = nil
    var id: String { url.absoluteString }
}

/// Local ordering only; never changes the remote PROPFIND request.
enum NativeWebDAVSortOrder {
    case ascending, descending
}

/// Immutable active connection. Editing the form must never send another
/// server's credentials to an existing listing or playback destination.
struct NativeWebDAVConnection {
    let root: URL
    private let username: String
    private let password: String

    init(address: String, username: String, password: String) throws {
        let root = try NativeWebDAV.rootURL(address, username: username, password: password)
        _ = try NativeWebDAV.authorization(username: username, password: password, root: root)
        self.root = root
        self.username = username
        self.password = password
    }

    func list(folder: URL) async throws -> [NativeWebDAVItem] {
        try await NativeWebDAV.list(root: root, folder: folder, username: username, password: password)
    }

    func authorization(for resource: URL) throws -> String? {
        guard NativeWebDAV.contains(resource, root: root) else { throw NativeWebDAVError.invalidFolder }
        return try NativeWebDAV.authorization(username: username, password: password, root: root)
    }
}

enum NativeWebDAVError: LocalizedError {
    case invalidAddress, insecureCredentials, invalidFolder, invalidResponse, responseTooLarge, unauthorized, httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "WebDAV 地址必须是无内嵌账号、查询参数的 HTTP(S) 目录 URL。"
        case .insecureCredentials: return "使用用户名或密码时必须连接 HTTPS WebDAV 服务。"
        case .invalidFolder: return "目录地址超出已连接的 WebDAV 根目录。"
        case .invalidResponse: return "WebDAV 目录响应无效或包含不安全的路径。"
        case .responseTooLarge: return "WebDAV 目录响应超过 1 MiB。"
        case .unauthorized: return "WebDAV 认证失败或没有访问权限。"
        case .httpStatus(let code): return "WebDAV 服务器返回 HTTP \(code)。"
        }
    }
}

/// Read-only RFC 4918 Depth:1 client. Credentials stay in memory and never enter URLs.
/// Only immediate same-origin children below the configured root are exposed.
enum NativeWebDAV {
    static func rootURL(_ raw: String, username: String = "", password: String = "") throws -> URL {
        guard raw.utf8.count <= 2048, raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 92 }),
              var parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              safeSegments(parts.percentEncodedPath) != nil else { throw NativeWebDAVError.invalidAddress }
        if !username.isEmpty || !password.isEmpty {
            guard scheme == "https", !username.isEmpty, !username.contains(":") else {
                throw NativeWebDAVError.insecureCredentials
            }
        }
        if !parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath += "/" }
        guard let url = parts.url else { throw NativeWebDAVError.invalidAddress }
        return url
    }

    static func authorization(username: String, password: String, root: URL) throws -> String? {
        guard !username.isEmpty || !password.isEmpty else { return nil }
        guard root.scheme?.lowercased() == "https", !username.isEmpty,
              username.utf8.count <= 256, password.utf8.count <= 1024,
              !username.contains(":"), !username.contains("\r"), !username.contains("\n"),
              !password.contains("\r"), !password.contains("\n") else {
            throw NativeWebDAVError.insecureCredentials
        }
        return "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    private static func safeSegments(_ path: String) -> [String]? {
        var result: [String] = []
        for encoded in path.split(separator: "/", omittingEmptySubsequences: false) {
            if encoded.isEmpty { continue }
            guard let segment = String(encoded).removingPercentEncoding,
                  !segment.isEmpty, segment != ".", segment != "..",
                  !segment.contains("/"), !segment.contains("\\"), !segment.contains("%"),
                  !segment.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            result.append(segment)
        }
        return result
    }

    private static func originMatches(_ lhs: URLComponents, _ rhs: URLComponents) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased() &&
        lhs.host?.lowercased() == rhs.host?.lowercased() &&
        (lhs.port ?? (lhs.scheme?.lowercased() == "https" ? 443 : 80)) ==
        (rhs.port ?? (rhs.scheme?.lowercased() == "https" ? 443 : 80))
    }

    private static func segments(_ url: URL, root: URL) -> [String]? {
        guard let current = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let base = URLComponents(url: root, resolvingAgainstBaseURL: false),
              originMatches(current, base), current.user == nil, current.password == nil,
              current.query == nil, current.fragment == nil,
              let basePath = safeSegments(base.percentEncodedPath),
              let path = safeSegments(current.percentEncodedPath),
              path.starts(with: basePath) else { return nil }
        return path
    }

    static func contains(_ folder: URL, root: URL) -> Bool { segments(folder, root: root) != nil }

    static func parse(_ data: Data, root: URL, folder: URL) throws -> [NativeWebDAVItem] {
        guard data.count <= 1_048_576 else { throw NativeWebDAVError.responseTooLarge }
        guard let folderSegments = segments(folder, root: root),
              let xml = String(data: data, encoding: .utf8),
              xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              xml.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw NativeWebDAVError.invalidResponse
        }
        let delegate = WebDAVXMLCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.sawMultistatus else { throw NativeWebDAVError.invalidResponse }
        var unique: [String: NativeWebDAVItem] = [:]
        for record in delegate.records {
            let href = record.href.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, href.utf8.count <= 4096,
                  !href.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 92 }),
                  let candidate = URL(string: href, relativeTo: folder)?.absoluteURL,
                  let path = segments(candidate, root: root),
                  path.count == folderSegments.count + 1, path.starts(with: folderSegments),
                  let name = path.last, name.count <= 180 else { continue }
            // URL.path omits a directory's trailing slash on Darwin. Appending
            // an empty component there changed an existing /Folder/ href into
            // /Folder// and broke the next PROPFIND on strict WebDAV servers.
            guard var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false) else { continue }
            if record.directory && !components.percentEncodedPath.hasSuffix("/") {
                components.percentEncodedPath += "/"
            }
            guard let normalized = components.url else { continue }
            let item = NativeWebDAVItem(url: normalized, name: name, isDirectory: record.directory,
                                        sizeBytes: record.directory ? nil : record.sizeBytes)
            unique[item.id] = item
        }
        return Array(unique.values).sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.prefix(200).map { $0 }
    }

    // Shared by URLSession's response callback and completion fallback. Some
    // URLSession implementations complete without a separate didReceive(response:)
    // callback. Never interpret that as a successful PROPFIND without validating
    // the final HTTP status and advertised body length.
    static func responseError(statusCode: Int, expectedLength: Int64, maxBytes: Int = 1_048_576) -> NativeWebDAVError? {
        if statusCode == 401 || statusCode == 403 { return .unauthorized }
        if statusCode != 207 { return .httpStatus(statusCode) }
        if expectedLength > Int64(maxBytes) { return .responseTooLarge }
        return nil
    }

    /// Untrusted optional byte metadata: decimal only, 0–8 TiB, no overflow.
    static func contentLength(_ raw: String) -> Int64? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 20,
              value.utf8.allSatisfy({ (48...57).contains($0) }),
              let bytes = Int64(value), bytes <= 8 * 1_099_511_627_776 else { return nil }
        return bytes
    }

    static func playable(_ item: NativeWebDAVItem) -> Bool {
        guard !item.isDirectory else { return false }
        return ["mp4", "m4v", "mov", "m3u8", "mp3", "m4a", "aac", "ts"].contains(item.url.pathExtension.lowercased())
    }

    /// Filter only the already validated Depth:1 listing. Keep folders visible
    /// in media-only mode so users can still navigate to playable files.
    /// Search is local, never interpolated into URLs, headers or PROPFIND XML.
    static func visibleEntries(_ entries: [NativeWebDAVItem], search: String, mediaOnly: Bool,
                               sortOrder: NativeWebDAVSortOrder = .ascending) -> [NativeWebDAVItem] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { item in
            (!mediaOnly || item.isDirectory || playable(item)) &&
            (term.isEmpty || item.name.localizedCaseInsensitiveContains(term))
        }.sorted { lhs, rhs in
            // Keep folders navigable at the top even in descending order.
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order == .orderedSame { return lhs.url.absoluteString < rhs.url.absoluteString }
            switch sortOrder {
            case .ascending: return order == .orderedAscending
            case .descending: return order == .orderedDescending
            }
        }
    }

    /// Return canonical ancestors inside the connected root only. Never derive
    /// a network destination from a displayed breadcrumb label.
    /// Limit the depth to avoid constructing unbounded navigation controls.
    static func navigationPath(root: URL, folder: URL) -> [URL] {
        guard let rootSegments = segments(root, root: root),
              contains(folder, root: root),
              URLComponents(url: folder, resolvingAgainstBaseURL: false)?.percentEncodedPath.hasSuffix("/") == true else { return [] }
        var path = [folder]
        var current = folder
        // Explicit default ports, host casing and equivalent encoded segments
        // may differ in URL serialization while still identifying this root.
        for _ in 0...32 {
            if segments(current, root: root) == rootSegments {
                path[path.count - 1] = root
                return Array(path.reversed())
            }
            guard path.count <= 32 else { return [] }
            let parent = current.deletingLastPathComponent()
            guard parent != current, contains(parent, root: root) else { return [] }
            path.append(parent)
            current = parent
        }
        return []
    }

    static func list(root: URL, folder: URL, username: String, password: String) async throws -> [NativeWebDAVItem] {
        guard contains(folder, root: root) else { throw NativeWebDAVError.invalidFolder }
        let auth = try authorization(username: username, password: password, root: root)
        var request = URLRequest(url: folder)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("<?xml version=\"1.0\" encoding=\"utf-8\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>".utf8)
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 15
        // The URLSession data delegate enforces the cap per received chunk,
        // before a server-controlled body can accumulate in application memory.
        let data = try await WebDAVBoundedTransport.load(request, maxBytes: 1_048_576)
        return try parse(data, root: root, folder: folder)
    }
}

/// Receives WebDAV XML in URLSession's bounded data chunks rather than
/// buffering an entire server response or iterating a million async bytes.
/// The URLSession delegate queue is serial; finish() is idempotent because
/// cancel/error callbacks may follow a rejected oversized response.
private final class WebDAVBoundedTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private var received = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var finished = false
    private var acceptedResponse = false

    private init(maxBytes: Int) { self.maxBytes = maxBytes }

    static func load(_ request: URLRequest, maxBytes: Int) async throws -> Data {
        let transport = WebDAVBoundedTransport(maxBytes: maxBytes)
        return try await transport.perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                self.continuation = continuation
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard !finished else { return }
        finished = true
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(NativeWebDAVError.invalidResponse))
            return
        }
        let failure = NativeWebDAV.responseError(
            statusCode: http.statusCode,
            expectedLength: response.expectedContentLength,
            maxBytes: maxBytes
        )
        if let failure {
            completionHandler(.cancel)
            finish(.failure(failure))
        } else {
            acceptedResponse = true
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        guard data.count <= maxBytes - received.count else {
            finish(.failure(NativeWebDAVError.responseTooLarge))
            dataTask.cancel()
            return
        }
        received.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard !finished else { return }
        // macOS URLSession can report a final HTTPURLResponse on the task
        // without invoking didReceive(response:). Apply the *same* rejection
        // policy in that case; never return unchecked bytes to the XML parser.
        if !acceptedResponse, let http = task.response as? HTTPURLResponse {
            if let failure = NativeWebDAV.responseError(
                statusCode: http.statusCode,
                expectedLength: http.expectedContentLength,
                maxBytes: maxBytes
            ) {
                finish(.failure(failure))
                return
            }
            acceptedResponse = true
        }
        if let error {
            finish(.failure(error))
        } else if acceptedResponse {
            finish(.success(received))
        } else {
            finish(.failure(NativeWebDAVError.invalidResponse))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // URLSession is allowed to finish a denied redirect without calling
        // didReceive(response:). Preserve the original 3xx status in either
        // callback ordering instead of surfacing a misleading invalidResponse.
        completionHandler(nil)
        finish(.failure(NativeWebDAVError.httpStatus(response.statusCode)))
    }
}

/// RFC 4918 multistatus collector. A response href is a direct child of
/// DAV:response; collection is authoritative only in a successful DAV:propstat.
/// Ignore similarly named foreign/nested elements and unsuccessful properties.
private final class WebDAVXMLCollector: NSObject, XMLParserDelegate {
    struct Record {
        var href = ""
        var directory = false
        var hasResourceType = false
        var invalidHref = false
        var sizeBytes: Int64?
        var invalidLength = false
    }
    private struct PropertyStatus {
        var status = ""
        var hasStatus = false
        var invalidStatus = false
        var hasResourceType = false
        var directory = false
        var lengthSeen = false
        var invalidLength = false
        var lengthText = ""
    }

    var records: [Record] = []
    var sawMultistatus = false
    private var path: [String] = []
    private var active: Record?
    private var property: PropertyStatus?
    private var responseStatus: String?
    private var duplicateResponseStatus = false
    private var seenHref = false

    private static func successfulStatus(_ raw: String) -> Bool {
        let parts = raw.split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"),
              parts[1].count == 3,
              parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              let code = Int(parts[1]) else { return false }
        return (200...299).contains(code)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let name = namespaceURI == "DAV:"
            ? (elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? "")
            : "#foreign"
        path.append(name)
        if path == ["multistatus"] { sawMultistatus = true }
        if path == ["multistatus", "response"] {
            active = Record()
            seenHref = false
            responseStatus = nil
            duplicateResponseStatus = false
        } else if path == ["multistatus", "response", "href"], active != nil {
            if seenHref { active?.invalidHref = true }
            seenHref = true
        } else if path == ["multistatus", "response", "status"] {
            if responseStatus != nil { duplicateResponseStatus = true }
            else { responseStatus = "" }
        } else if path == ["multistatus", "response", "propstat"] {
            property = PropertyStatus()
        } else if path == ["multistatus", "response", "propstat", "status"] {
            if property?.hasStatus == true { property?.invalidStatus = true }
            property?.hasStatus = true
        } else if path == ["multistatus", "response", "propstat", "prop", "resourcetype"] {
            property?.hasResourceType = true
        } else if path == ["multistatus", "response", "propstat", "prop", "resourcetype", "collection"] {
            property?.directory = true
        } else if path == ["multistatus", "response", "propstat", "prop", "getcontentlength"] {
            if property?.lengthSeen == true { property?.invalidLength = true }
            property?.lengthSeen = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path == ["multistatus", "response", "href"] {
            active?.href += string
        } else if path == ["multistatus", "response", "status"] {
            responseStatus? += string
        } else if path == ["multistatus", "response", "propstat", "status"] {
            property?.status += string
        } else if path == ["multistatus", "response", "propstat", "prop", "getcontentlength"] {
            property?.lengthText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if path == ["multistatus", "response", "propstat"] {
            if let property, property.hasStatus, !property.invalidStatus,
               Self.successfulStatus(property.status), var record = active {
                if property.hasResourceType {
                    record.hasResourceType = true
                    record.directory = record.directory || property.directory
                }
                // Ignore failed/foreign/nested properties and conflicting values.
                // Malformed metadata must not hide an otherwise valid file.
                if property.lengthSeen {
                    if property.invalidLength || record.invalidLength {
                        record.sizeBytes = nil
                        record.invalidLength = true
                    } else if let bytes = NativeWebDAV.contentLength(property.lengthText) {
                        if let existing = record.sizeBytes, existing != bytes {
                            record.sizeBytes = nil
                            record.invalidLength = true
                        } else { record.sizeBytes = bytes }
                    } else {
                        record.sizeBytes = nil
                        record.invalidLength = true
                    }
                }
                active = record
            }
            property = nil
        } else if path == ["multistatus", "response"] {
            if let active, !active.invalidHref, active.hasResourceType,
               !duplicateResponseStatus,
               responseStatus.map(Self.successfulStatus) ?? true,
               records.count < 501 {
                records.append(active)
            }
            self.active = nil
        }
        if !path.isEmpty { path.removeLast() }
    }
}
