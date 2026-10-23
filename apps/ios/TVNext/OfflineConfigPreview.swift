import Foundation

/// Offline-only, bounded FongMi JSON metadata preview. Does not execute or fetch providers.
struct OfflineConfigSite: Identifiable {
    let key: String
    let name: String
    let type: Int?
    let searchable: Bool
    let hidden: Bool
    let categories: [String]
    var id: String { key }
}

struct OfflineConfigPreview {
    let sites: [OfflineConfigSite]
    let liveSourceCount: Int
    let spiderDeclared: Bool
    let warnings: [String]
}

enum OfflineConfigError: LocalizedError {
    case empty, tooLarge, invalidJSON, invalidRoot, invalidSites, invalidLives

    var errorDescription: String? {
        switch self {
        case .empty: return "JSON 配置为空。"
        case .tooLarge: return "JSON 配置不能超过 1 MiB（UTF-8）。"
        case .invalidJSON: return "JSON 格式无效。"
        case .invalidRoot: return "JSON 顶层必须是对象。"
        case .invalidSites: return "sites 必须是数组。"
        case .invalidLives: return "lives 必须是数组。"
        }
    }
}

enum OfflineConfigParser {
    static let maxBytes = 1_048_576

    static func parse(_ content: String) throws -> OfflineConfigPreview {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineConfigError.empty
        }
        guard content.utf8.count <= maxBytes else { throw OfflineConfigError.tooLarge }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: Data(content.utf8))
        } catch {
            throw OfflineConfigError.invalidJSON
        }
        guard let root = value as? [String: Any] else { throw OfflineConfigError.invalidRoot }
        if root["sites"] != nil && !(root["sites"] is [Any]) { throw OfflineConfigError.invalidSites }
        if root["lives"] != nil && !(root["lives"] is [Any]) { throw OfflineConfigError.invalidLives }

        let rawSites = root["sites"] as? [Any] ?? []
        let rawLives = root["lives"] as? [Any] ?? []
        var warnings: [String] = []
        if rawSites.count > 1000 { warnings.append("只显示前 1000 个站点。") }
        if rawLives.count > 50 { warnings.append("直播源预览最多显示 50 个。") }

        var seen = Set<String>()
        var sites: [OfflineConfigSite] = []
        for item in rawSites.prefix(1000) {
            guard let site = item as? [String: Any] else { continue }
            let key = clipped(site["key"], max: 200)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let name = clipped(site["name"], max: 200)
            let categories = (site["categories"] as? [Any] ?? [])
                .prefix(50)
                .compactMap { item -> String? in
                    let text = clipped(item, max: 100)
                    return text.isEmpty ? nil : text
                }
            sites.append(OfflineConfigSite(
                key: key, name: name.isEmpty ? key : name,
                type: site["type"] as? Int,
                searchable: (site["searchable"] as? Int) != 0,
                hidden: (site["hide"] as? Int) == 1,
                categories: categories
            ))
        }
        return OfflineConfigPreview(
            sites: sites, liveSourceCount: rawLives.count,
            spiderDeclared: !clipped(root["spider"], max: 1024).isEmpty,
            warnings: warnings
        )
    }

    private static func clipped(_ value: Any?, max: Int) -> String {
        guard let value = value as? String else { return "" }
        return String(value.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
