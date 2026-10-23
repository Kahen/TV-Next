import Foundation

struct NativeSubscription: Decodable {
    struct Site: Decodable, Identifiable {
        let key: String; let name: String; let type: Int; let searchable: Bool; let hidden: Bool; let support: String
        var id: String { key }
        var supported: Bool { [0,1,2,4].contains(type) }
    }
    struct Depot: Decodable, Identifiable { let name: String; let url: String; var id: String { url } }
    let content: String; let url: String; let sites: [Site]; let depots: [Depot]; let liveCount: Int; let warnings: [String]
}
struct NativeMediaItem: Decodable, Identifiable {
    let id: String; let name: String; let remarks: String?; let folder: Bool?; let action: String?
}
struct NativeMediaPage: Decodable {
    struct Category: Decodable, Identifiable { let id: String; let name: String }
    let categories: [Category]; let items: [NativeMediaItem]; let total: Int; let page: Int; let hasMore: Bool
}
struct NativeMediaDetail: Decodable {
    struct Episode: Decodable { let name: String; let playable: Bool }
    struct Line: Decodable { let name: String; let episodes: [Episode] }
    let item: NativeMediaItem; let description: String?; let lines: [Line]
}
struct NativePlaybackResource: Decodable, Identifiable { let name: String; let url: String; var id: String { url } }
struct NativeMediaPlayback: Decodable {
    let url: String; let name: String; let lineName: String; let headers: [String:String]
    let danmaku: [NativePlaybackResource]; let subtitles: [NativePlaybackResource]
}
struct NativeSiteRequest: Encodable {
    var content = ""; var url = ""; var siteKey = ""; var categoryId: String?; var query: String?; var vodId: String?
    var page = 1; var lineIndex = 0; var episodeIndex = 0
}
struct NativeSubscriptionRequest: Encodable { let content: String; let url: String }
struct NativeResourceRequest: Encodable { let url: String }
struct NativeTextResponse: Decodable { let content: String }

extension TVNextAPI {
    func get<T: Decodable>(_ operation: String) async throws -> T {
        guard let scheme=server.scheme?.lowercased(),["http","https"].contains(scheme),server.host != nil,server.user == nil,server.password == nil else { throw APIError.invalidServer }
        var request=URLRequest(url:server.appending(path:"api/v1/"+operation));request.timeoutInterval=20
        if let token { request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization") }
        let (bytes,response)=try await URLSession.shared.bytes(for:request)
        var data=Data()
        for try await byte in bytes { if data.count>=4_194_304 { throw APIError.serverRejected };data.append(byte) }
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else {
            let error=try? JSONDecoder().decode([String:String].self,from:data)
            throw NativeRequestError.message(error?["error"] ?? "服务器请求失败")
        }
        return try JSONDecoder().decode(T.self,from:data)
    }

    func request<T: Decodable, Body: Encodable>(_ operation: String, body: Body) async throws -> T {
        guard let scheme = server.scheme?.lowercased(), ["http","https"].contains(scheme),
              server.host != nil, server.user == nil, server.password == nil else { throw APIError.invalidServer }
        var request = URLRequest(url: server.appending(path: "api/v1/" + operation))
        request.httpMethod = "POST"; request.timeoutInterval = 20
        if let token { request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        var data = Data()
        for try await byte in bytes {
            if data.count >= 4_194_304 { throw APIError.serverRejected }
            data.append(byte)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let error = try? JSONDecoder().decode([String:String].self,from:data)
            throw NativeRequestError.message(error?["error"] ?? "服务器请求失败")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
enum NativeRequestError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let value): return value } }
}

struct NativeCloudRequest: Encodable { let server: String; let token: String; let path: String; let password: String; let page: Int }
struct NativeCloudPage: Decodable {
    struct Entry: Decodable, Identifiable { let name: String; let directory: Bool; let size: Int64; var id: String { name } }
    let path: String; let entries: [Entry]; let page: Int; let hasMore: Bool
}
struct NativeCloudPlayback: Decodable { let url: String; let name: String; let headers: [String:String] }

struct NativeLiveRequest: Encodable { let content: String; let url: String; let liveIndex: Int }
struct NativeLiveResponse: Decodable { let channels: [TVChannel]; let warnings: [String] }
