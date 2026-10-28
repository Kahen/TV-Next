import Foundation

struct NativeTimeshift: Codable, Equatable {
    let url: String; let start: Int64; let window: Int64
    func range(now: Int64) -> ClosedRange<Int64>? {
        guard start > 0, start < now, window > 0,
              url.range(of: #"\{time\}|%7Btime%7D"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return max(start, now - window)...now
    }
}
struct NativeCatchup: Codable, Equatable {
    var type = "append"; var days = "7"; var source: String; var regex = ""; var replace = ""
}
struct NativeReplaySession: Codable, Equatable {
    let path: String; let expiresAt: Int64; let hls: Bool; let time: Int64
}
struct NativeReplayRequest: Encodable {
    let channel: TVChannel; let time: Int64; let stop: Int64?; let timezone: String
}

struct TVChannel: Codable, Identifiable, Equatable {
    let name: String
    let url: String
    let group: String
    let logo: String?
    let tvgId: String?
    var headers: [String:String]? = nil
    var headersRequired: Bool? = nil
    var timeshift: NativeTimeshift? = nil
    var catchup: NativeCatchup? = nil
    // A relay capability belongs to the active player only and is never encoded.
    var replay: NativeReplaySession? = nil
    private enum CodingKeys: String, CodingKey { case name, url, group, logo, tvgId, headers, headersRequired, timeshift, catchup }

    var id: String { group + "|" + name + "|" + url }
}

struct TVPlaylistResponse: Decodable {
    let channels: [TVChannel]
    let total: Int
}

private struct TextImportRequest: Encodable {
    let content: String
}

struct TVNextAPI {
    let server: URL
    var token: String? = nil

    func parsePlaylist(_ content: String) async throws -> [TVChannel] {
        guard let scheme = server.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw APIError.invalidServer
        }
        let endpoint = server.appending(path: "api/v1/playlists/parse")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TextImportRequest(content: content))
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverRejected
        }
        return try JSONDecoder().decode(TVPlaylistResponse.self, from: data).channels
    }
}

enum APIError: LocalizedError {
    case invalidServer
    case serverRejected

    var errorDescription: String? {
        switch self {
        case .invalidServer: return "服务器 URL 必须使用 http 或 https。"
        case .serverRejected: return "服务器无法解析播放列表，请检查地址与输入内容。"
        }
    }
}
