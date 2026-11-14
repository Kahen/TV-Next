import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicitly selected WebDAV subtitles, fetched on-device with the immutable
/// connection's credentials. No redirects, shared cookies, cache or persistence.
enum NativeWebDAVCaptionReader {
    static let maxBytes = 1_048_576

    static func supported(_ item: NativeWebDAVItem) -> Bool {
        !item.isDirectory && ["srt", "vtt", "ass", "ssa"].contains(item.url.pathExtension.lowercased())
    }

    static func request(for item: NativeWebDAVItem, connection: NativeWebDAVConnection) throws -> URLRequest {
        guard supported(item), NativeWebDAV.contains(item.url, root: connection.root) else {
            throw NativeWebDAVError.invalidFolder
        }
        if let size = item.sizeBytes, size > Int64(maxBytes) { throw CaptionError.tooLarge }
        var request = URLRequest(url: item.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/plain, text/vtt, application/octet-stream", forHTTPHeaderField: "Accept")
        if let authorization = try connection.authorization(for: item.url) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func load(_ item: NativeWebDAVItem, connection: NativeWebDAVConnection,
                     encoding: CaptionTextEncoding = .unicode) async throws -> [CaptionCue] {
        try Task<Never, Never>.checkCancellation()
        let request = try request(for: item, connection: connection)
        let data = try await WebDAVBoundedTransport.load(request, maxBytes: maxBytes, expectedStatus: 200)
        try Task<Never, Never>.checkCancellation()
        return try CaptionParser.parse(data, encoding: encoding)
    }
}
