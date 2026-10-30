import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

enum NativeDLNAError: LocalizedError, Equatable {
    case invalidRenderer, invalidMedia, unsupportedMedia, invalidSeek, unsupportedSeek, responseTooLarge, invalidResponse, httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRenderer: return "DLNA 控制地址必须是局域网 IPv4 HTTP 地址，且不能包含凭据、查询或重定向。"
        case .invalidMedia: return "只能投屏不带凭据的直接 HTTP(S) 媒体地址。"
        case .unsupportedMedia: return "当前媒体需要额外请求头、重放解析或本地文件，不能直接交给 DLNA 设备。"
        case .invalidSeek: return "DLNA 跳转位置无效，必须位于 00:00:00 至 99:59:59。"
        case .unsupportedSeek: return "设备未处于播放/暂停状态，或没有可跳转的有限时长媒体。"
        case .responseTooLarge: return "DLNA 设备返回的数据超过 32 KiB。"
        case .invalidResponse: return "DLNA 设备响应无效或返回 SOAP Fault。"
        case .httpStatus(let status): return "DLNA 设备返回 HTTP \(status)。"
        }
    }
}

enum NativeDLNAAction: String {
    case setURI = "SetAVTransportURI", play = "Play", pause = "Pause", stop = "Stop", getTransportInfo = "GetTransportInfo", getPositionInfo = "GetPositionInfo", seek = "Seek"
}

/// Manual, opt-in AVTransport subset. No SSDP, arbitrary hosts or credentialed streams.
enum NativeDLNA {
    static let service = "urn:schemas-upnp-org:service:AVTransport:1"
    static let maxResponseBytes = 32_768

    static func rendererURL(_ raw: String) throws -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 512,
              let parts = URLComponents(string: text), parts.scheme?.lowercased() == "http",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let host = parts.host, privateIPv4(host),
              let port = parts.port, (1...65535).contains(port),
              parts.percentEncodedPath.count > 1, parts.percentEncodedPath.utf8.count <= 256,
              !parts.percentEncodedPath.contains("%"),
              !parts.percentEncodedPath.split(separator: "/").contains(".."),
              let url = parts.url else { throw NativeDLNAError.invalidRenderer }
        return url
    }

    private static func privateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  part.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  (part.count == 1 || part.first != "0"),
                  let value = Int(part), value <= 255 else { return false }
            octets.append(value)
        }
        return octets[0] == 10 || octets[0] == 127 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168)
    }

    static func mediaURL(_ raw: String, hasHeaders: Bool = false, replay: Bool = false) throws -> URL {
        guard !hasHeaders, !replay else { throw NativeDLNAError.unsupportedMedia }
        guard raw.utf8.count <= 4096, let parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil, let url = parts.url else { throw NativeDLNAError.invalidMedia }
        return url
    }

    private static func xmlEscaped(_ input: String) -> String {
        input.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func request(_ action: NativeDLNAAction, endpoint: URL, media: URL? = nil, seekSeconds: Int? = nil) throws -> URLRequest {
        if action == .setURI && media == nil { throw NativeDLNAError.invalidMedia }
        if action == .seek && seekSeconds == nil { throw NativeDLNAError.invalidSeek }
        if action != .seek && seekSeconds != nil { throw NativeDLNAError.invalidSeek }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service)#\(action.rawValue)\"", forHTTPHeaderField: "SOAPACTION")
        request.setValue("close", forHTTPHeaderField: "Connection")
        let argument: String
        switch action {
        case .setURI:
            argument = "<CurrentURI>\(xmlEscaped(media!.absoluteString))</CurrentURI><CurrentURIMetaData></CurrentURIMetaData>"
        case .play: argument = "<Speed>1</Speed>"
        case .seek:
            let target = try NativeDLNASeek.target(seekSeconds!)
            argument = "<Unit>REL_TIME</Unit><Target>\(target)</Target>"
        case .pause, .stop, .getTransportInfo, .getPositionInfo: argument = ""
        }
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\(action.rawValue) xmlns:u="\(service)"><InstanceID>0</InstanceID>\(argument)</u:\(action.rawValue)></s:Body></s:Envelope>
        """
        request.httpBody = Data(body.utf8)
        return request
    }

    static func validate(_ data: Data, response: URLResponse, action: NativeDLNAAction) throws {
        guard data.count <= maxResponseBytes else { throw NativeDLNAError.responseTooLarge }
        guard let http = response as? HTTPURLResponse else { throw NativeDLNAError.invalidResponse }
        guard http.statusCode == 200 else { throw NativeDLNAError.httpStatus(http.statusCode) }
        guard let body = String(data: data, encoding: .utf8),
              !body.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !body.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw NativeDLNAError.invalidResponse
        }
        let parser = XMLParser(data: Data(body.utf8))
        let collector = NativeDLNAResponseParser(action: action)
        parser.delegate = collector
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), collector.valid else { throw NativeDLNAError.invalidResponse }
    }

    static func send(_ action: NativeDLNAAction, endpoint: URL, media: URL? = nil, seekSeconds: Int? = nil) async throws {
        let approved = try rendererURL(endpoint.absoluteString)
        let checkedMedia = try media.map { try mediaURL($0.absoluteString) }
        let request = try request(action, endpoint: approved, media: checkedMedia, seekSeconds: seekSeconds)
        let (data, response) = try await NativeDLNABoundedTransport.load(request, maxBytes: maxResponseBytes)
        try validate(data, response: response, action: action)
    }

    static func cast(endpoint: URL, media: URL) async throws {
        try await send(.setURI, endpoint: endpoint, media: media)
        try Task.checkCancellation()
        try await send(.play, endpoint: endpoint)
    }
}

/// Strict 32 KiB streaming cap, no redirects, no cookies, finite request timeout.
final class NativeDLNABoundedTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private var received = Data()
    private var response: URLResponse?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var finished = false
    private var cancelled = false
    private let completionLock = NSLock()

    private init(maxBytes: Int) { self.maxBytes = maxBytes }

    static func load(_ request: URLRequest, maxBytes: Int) async throws -> (Data, URLResponse) {
        let delegate = NativeDLNABoundedTransport(maxBytes: maxBytes)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForResource = 8
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        // Create the task before cancellation is registered. Cancelling a task
        // never invalidates its session before URLSession creates that task.
        let task = session.dataTask(with: request)
        let deadline = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { delegate.abort(task, error: URLError(.timedOut)) }
        }
        defer { deadline.cancel(); session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                delegate.begin(continuation, task: task)
            }
        } onCancel: {
            delegate.abort(task, error: CancellationError())
        }
    }

    private func begin(_ pending: CheckedContinuation<(Data, URLResponse), Error>, task: URLSessionDataTask) {
        completionLock.lock()
        if cancelled || finished {
            completionLock.unlock()
            pending.resume(throwing: CancellationError())
            return
        }
        continuation = pending
        completionLock.unlock()
        task.resume()
    }

    private func abort(_ task: URLSessionDataTask, error: Error) {
        completionLock.lock()
        cancelled = true
        completionLock.unlock()
        // Resolve the continuation with the intended cancellation/deadline
        // error before URLSession can race to report NSURLErrorCancelled.
        finish(.failure(error))
        task.cancel()
    }

    private var isFinished: Bool {
        completionLock.lock()
        defer { completionLock.unlock() }
        return finished
    }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        completionLock.lock()
        guard !finished else { completionLock.unlock(); return }
        finished = true
        let pending = continuation
        continuation = nil
        completionLock.unlock()
        pending?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              response.expectedContentLength <= Int64(maxBytes) else {
            completionHandler(.cancel)
            let status = (response as? HTTPURLResponse)?.statusCode
            finish(.failure(status == 200 ? NativeDLNAError.responseTooLarge : NativeDLNAError.httpStatus(status ?? 0)))
            return
        }
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isFinished else { return }
        guard data.count <= maxBytes - received.count else {
            finish(.failure(NativeDLNAError.responseTooLarge))
            dataTask.cancel()
            return
        }
        received.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isFinished else { return }
        let finalResponse = response ?? task.response
        guard let http = finalResponse as? HTTPURLResponse else {
            finish(.failure(error ?? NativeDLNAError.invalidResponse)); return
        }
        guard http.statusCode == 200 else {
            finish(.failure(NativeDLNAError.httpStatus(http.statusCode))); return
        }
        guard http.expectedContentLength <= Int64(maxBytes) else {
            finish(.failure(NativeDLNAError.responseTooLarge)); return
        }
        if let error { finish(.failure(error)) }
        else { finish(.success((received, http))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(NativeDLNAError.httpStatus(response.statusCode)))
    }
}

private final class NativeDLNAResponseParser: NSObject, XMLParserDelegate {
    private let action: NativeDLNAAction
    private var stack: [(String, String)] = []
    private var invalid = false
    private var foundResponse = false
    var valid: Bool { !invalid && foundResponse && stack.isEmpty }

    init(action: NativeDLNAAction) { self.action = action }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let ns = namespaceURI ?? ""
        if stack.isEmpty && (elementName != "Envelope" || ns != "http://schemas.xmlsoap.org/soap/envelope/") { invalid = true }
        if stack.count == 1 && (elementName != "Body" || ns != "http://schemas.xmlsoap.org/soap/envelope/") { invalid = true }
        if stack.count == 2 {
            if elementName == "\(action.rawValue)Response" && ns == NativeDLNA.service && !foundResponse {
                foundResponse = true
            } else { invalid = true }
        }
        if elementName == "Fault" { invalid = true }
        stack.append((elementName, ns))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard let last = stack.popLast(), last.0 == elementName, last.1 == (namespaceURI ?? "") else {
            invalid = true
            return
        }
    }
}
