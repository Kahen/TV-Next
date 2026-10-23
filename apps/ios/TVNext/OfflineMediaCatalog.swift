import Foundation
import CoreFoundation

/// Offline-only FongMi Result JSON subset, independent of network/Spider runtime.
struct OfflineMediaCategory: Equatable, Identifiable {
    let id: String
    let name: String
}
struct OfflineMediaEpisode: Equatable, Identifiable {
    let name: String
    let directURL: String?
    var id: String { name + "|" + (directURL ?? "") }
}
struct OfflineMediaLine: Equatable {
    let name: String
    let episodes: [OfflineMediaEpisode]
}
struct OfflineMediaVideo: Identifiable, Equatable {
    let id: String
    let name: String
    let categoryId: String?
    let categoryName: String?
    let remarks: String?
    let year: String?
    let description: String?
    let director: String?
    let actors: String?
    let lines: [OfflineMediaLine]
}
struct OfflineMediaCatalog {
    let categories: [OfflineMediaCategory]
    let videos: [OfflineMediaVideo]

    func category(_ id: String) -> [OfflineMediaVideo] {
        videos.filter { $0.categoryId == id || ($0.categoryId == nil && $0.categoryName == id) }
    }
    func search(_ term: String) -> [OfflineMediaVideo] {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return videos }
        return videos.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

enum OfflineMediaError: LocalizedError, Equatable {
    case empty, tooLarge, invalidJSON, invalidRoot, invalidCollections, tooManyEntries

    var errorDescription: String? {
        switch self {
        case .empty: return "影视数据为空。"
        case .tooLarge: return "影视 JSON 超过 1 MiB。"
        case .invalidJSON: return "无法解析影视 JSON，请检查 UTF-8 格式。"
        case .invalidRoot: return "影视数据必须是 FongMi Result JSON 对象。"
        case .invalidCollections: return "Result 的 class 和 list 必须是数组。"
        case .tooManyEntries: return "分类最多 200 项，影视最多 2000 项。"
        }
    }
}

/// Parses only supplied text. No downloads, script evaluation, image requests or persistence.
/// The recognized vod_* metadata is a bounded subset of FongMi Result, not a Spider runtime.
enum OfflineMediaParser {
    static let maxBytes = 1_048_576

    static func parse(_ text: String) throws -> OfflineMediaCatalog {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineMediaError.empty
        }
        guard text.utf8.count <= maxBytes else { throw OfflineMediaError.tooLarge }
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            throw OfflineMediaError.invalidJSON
        }
        guard let root = decoded as? [String: Any] else { throw OfflineMediaError.invalidRoot }
        guard root["class"] != nil || root["list"] != nil else { throw OfflineMediaError.invalidCollections }
        if let value = root["class"], !(value is [Any]) { throw OfflineMediaError.invalidCollections }
        if let value = root["list"], !(value is [Any]) { throw OfflineMediaError.invalidCollections }
        let categoryNodes = root["class"] as? [Any] ?? []
        let videoNodes = root["list"] as? [Any] ?? []
        guard categoryNodes.count <= 200, videoNodes.count <= 2_000 else {
            throw OfflineMediaError.tooManyEntries
        }
        var ids = Set<String>()
        let categories: [OfflineMediaCategory] = categoryNodes.compactMap { element in
            guard let entry = element as? [String: Any] else { return nil }
            let id = field(entry, "type_id", limit: 100)
            guard !id.isEmpty, ids.insert(id).inserted else { return nil }
            let label = field(entry, "type_name", limit: 150)
            return OfflineMediaCategory(id: id, name: label.isEmpty ? id : label)
        }
        ids.removeAll()
        let videos: [OfflineMediaVideo] = videoNodes.compactMap { element in
            guard let entry = element as? [String: Any] else { return nil }
            let id = field(entry, "vod_id", limit: 200)
            let name = field(entry, "vod_name", limit: 200)
            guard !id.isEmpty, !name.isEmpty, ids.insert(id).inserted else { return nil }

            let names = field(entry, "vod_play_from", limit: 2_000)
                .components(separatedBy: "$$$").prefix(30).filter { !$0.isEmpty }
            let sources = field(entry, "vod_play_url", limit: maxBytes)
                .components(separatedBy: "$$$").prefix(30)
            var lines: [OfflineMediaLine] = []
            for (index, line) in names.enumerated() {
                let raw = index < sources.count ? sources[sources.index(sources.startIndex, offsetBy: index)] : ""
                let episodes = raw.components(separatedBy: "#").prefix(400).compactMap { value -> OfflineMediaEpisode? in
                    guard !value.isEmpty else { return nil }
                    let separator = value.firstIndex(of: "$")
                    let label = separator.map { String(value[..<$0]) } ?? "Episode"
                    let target = separator.map { String(value[value.index(after: $0)...]) } ?? value
                    let url = MediaAddress.valid(target) ? target : nil
                    return OfflineMediaEpisode(name: String(label.prefix(150)), directURL: url)
                }
                if !episodes.isEmpty {
                    lines.append(OfflineMediaLine(name: String(line.prefix(120)), episodes: episodes))
                }
            }
            return OfflineMediaVideo(
                id: id, name: name,
                categoryId: optional(entry, "type_id", limit: 100),
                categoryName: optional(entry, "type_name", limit: 150),
                remarks: optional(entry, "vod_remarks", limit: 150),
                year: optional(entry, "vod_year", limit: 30),
                description: optional(entry, "vod_content", limit: 2_000),
                director: optional(entry, "vod_director", limit: 300),
                actors: optional(entry, "vod_actor", limit: 300),
                lines: lines
            )
        }
        return OfflineMediaCatalog(categories: categories, videos: videos)
    }

    private static func optional(_ dict: [String: Any], _ key: String, limit: Int) -> String? {
        let value = field(dict, key, limit: limit)
        return value.isEmpty ? nil : value
    }

    private static func field(_ dict: [String: Any], _ key: String, limit: Int) -> String {
        let value = dict[key]
        let raw: String
        if let text = value as? String {
            raw = text
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            raw = number.stringValue
        } else {
            return ""
        }
        return String(raw.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
