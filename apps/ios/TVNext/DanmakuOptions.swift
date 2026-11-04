import Foundation

/// Device-local presentation preferences; never stores media URLs or comment payloads.
struct DanmakuOptions: Equatable, Codable {
    var enabled = true
    var opacity = 0.8
    var fontSize = 22.0
    var area = 0.5
    var duration = 8.0
    var offset = 0.0
    var blocked = ""
}

enum DanmakuOptionsStore {
    static let key = "tv-next-native-danmaku-options-v1"
    private static let maximumBytes = 8_192

    private static func valid(_ options: DanmakuOptions) -> Bool {
        options.opacity.isFinite && (0.1...1).contains(options.opacity) &&
        options.fontSize.isFinite && (12...40).contains(options.fontSize) &&
        options.area.isFinite && (0.25...1).contains(options.area) &&
        options.duration.isFinite && (4...15).contains(options.duration) &&
        options.offset.isFinite && (-120...120).contains(options.offset) &&
        options.blocked.utf8.count <= 4_096
    }

    /// Limit editable blocked words on Unicode scalar boundaries, never splitting UTF-8.
    static func boundedBlocked(_ raw: String) -> String {
        guard raw.utf8.count > 4_096 else { return raw }
        var remaining = 4_096
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            let bytes = scalar.utf8.count
            if bytes > remaining { break }
            scalars.append(scalar)
            remaining -= bytes
        }
        return String(scalars)
    }

    static func load(from defaults: UserDefaults = .standard) -> DanmakuOptions {
        guard let data = defaults.data(forKey: key), data.count <= maximumBytes,
              let value = try? JSONDecoder().decode(DanmakuOptions.self, from: data),
              valid(value) else { return DanmakuOptions() }
        return value
    }

    @discardableResult
    static func save(_ options: DanmakuOptions, to defaults: UserDefaults = .standard) -> Bool {
        guard valid(options), let data = try? JSONEncoder().encode(options),
              data.count <= maximumBytes else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
