import Foundation

struct TVChannel: Codable, Identifiable {
    let name: String
    let url: String
    let group: String
    let logo: String?
    let tvgId: String?
    var headers: [String:String]? = nil
    var headersRequired: Bool? = nil

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
