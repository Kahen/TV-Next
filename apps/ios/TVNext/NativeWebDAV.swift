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
    var id: String { url.absoluteString }
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
              username.count <= 256, password.count <= 1024,
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
            let normalized = record.directory && !candidate.path.hasSuffix("/")
                ? candidate.appendingPathComponent("", isDirectory: true) : candidate
            let item = NativeWebDAVItem(url: normalized, name: name, isDirectory: record.directory)
            unique[item.id] = item
        }
        return Array(unique.values).sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.prefix(200).map { $0 }
    }

    static func playable(_ item: NativeWebDAVItem) -> Bool {
        guard !item.isDirectory else { return false }
        return ["mp4", "m4v", "mov", "m3u8", "mp3", "m4a", "aac", "ts"].contains(item.url.pathExtension.lowercased())
    }

    static func list(root: URL, folder: URL, username: String, password: String) async throws -> [NativeWebDAVItem] {
        guard contains(folder, root: root) else { throw NativeWebDAVError.invalidFolder }
        let auth = try authorization(username: username, password: password, root: root)
        var request = URLRequest(url: folder)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("<?xml version=\"1.0\" encoding=\"utf-8\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/></d:prop></d:propfind>".utf8)
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 15
        let session = URLSession(configuration: .ephemeral, delegate: WebDAVNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NativeWebDAVError.invalidResponse }
        if response.statusCode == 401 || response.statusCode == 403 { throw NativeWebDAVError.unauthorized }
        guard response.statusCode == 207 else { throw NativeWebDAVError.httpStatus(response.statusCode) }
        return try parse(data, root: root, folder: folder)
    }
}

private final class WebDAVNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class WebDAVXMLCollector: NSObject, XMLParserDelegate {
    struct Record { var href = ""; var directory = false }
    var records: [Record] = []
    var sawMultistatus = false
    private var active: Record?
    private var inHref = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? ""
        if name == "multistatus" && namespaceURI == "DAV:" { sawMultistatus = true }
        guard namespaceURI == "DAV:" else { return }
        if name == "response" { active = Record() }
        if name == "href" && active != nil { inHref = true }
        if name == "collection" && active != nil { active?.directory = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inHref { active?.href += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard namespaceURI == "DAV:" else { return }
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? ""
        if name == "href" { inHref = false }
        if name == "response", let record = active {
            if records.count < 501 { records.append(record) }
            active = nil
        }
    }
}
