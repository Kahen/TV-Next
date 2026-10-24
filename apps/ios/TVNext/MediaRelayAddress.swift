import Foundation

struct NativeRelayRequest: Encodable { let url: String; let headers: [String:String] }
struct NativeRelayResponse: Decodable { let path: String; let expiresAt: Int64 }
enum MediaRelayAddress {
    static func resolve(_ path: String,server: URL) throws -> (url: URL,ticket: String) {
        guard path.range(of:"^/api/v1/home/media/[A-Za-z0-9_-]{43}/0$",options:.regularExpression) != nil,
              var parts=URLComponents(url:server,resolvingAgainstBaseURL:false),
              ["http","https"].contains(parts.scheme?.lowercased() ?? ""),parts.host != nil,parts.user == nil,parts.password == nil else {
            throw URLError(.badURL)
        }
        parts.path=path;parts.query=nil;parts.fragment=nil
        guard let url=parts.url else { throw URLError(.badURL) }
        return (url,String(path.split(separator:"/")[4]))
    }
}
