import Foundation

struct NativeEpgProgram: Decodable {
    let start: String; let stop: String; let title: String; let description: String?
    var range: String {
        let parser=ISO8601DateFormatter()
        let formatter=DateFormatter();formatter.dateStyle = .none;formatter.timeStyle = .short
        guard let from=parser.date(from:start),let until=parser.date(from:stop) else { return "时间无效" }
        return formatter.string(from:from)+" – "+formatter.string(from:until)
    }
}
struct NativeEpgChannel: Decodable {
    let id: String?;let name: String;let matchedChannelId: String?;let matchType: String
    let current: NativeEpgProgram?;let upcoming: [NativeEpgProgram]
}
struct NativeEpgGuide: Decodable {
    let generatedAt: String;let until: String;let totalChannels: Int;let matchedChannels: Int
    let channels: [NativeEpgChannel];let warnings: [String]
}
struct NativeEpgFeed: Decodable, Identifiable {
    let id: String;let name: String;let url: String;let intervalMinutes: Int;let enabled: Bool
    let updatedAt: Int64;let nextRefresh: Int64;let lastError: String?;let available: Bool
}
struct NativeEpgChannelRequest: Encodable { let id: String?;let name: String }
struct NativeEpgRequest: Encodable {
    var xml: String? = nil
    let channels: [NativeEpgChannelRequest]
    var hours=12
}
struct NativeEpgFeedWrite: Encodable { let name: String;let url: String;let intervalMinutes: Int;var enabled=true }
