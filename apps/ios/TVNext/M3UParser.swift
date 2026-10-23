import Foundation

enum PlaylistError: LocalizedError {
    case empty
    case tooLarge
    case tooManyLines

    var errorDescription: String? {
        switch self {
        case .empty: return "M3U 内容为空。"
        case .tooLarge: return "M3U 内容超过 1 MiB。"
        case .tooManyLines: return "M3U 行数超过 20000 行。"
        }
    }
}

enum MediaAddress {
    static func valid(_ value: String) -> Bool {
        guard value.count <= 2048, value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else {
            return false
        }
        return true
    }
}

/// Offline parser for a safe, well-defined M3U subset; no network requests or code execution.
enum M3UParser {
    private static let attributeRegex = try! NSRegularExpression(
        pattern: #"([A-Za-z0-9_-]+)\s*=\s*"([^"]*)""#,
        options: []
    )

    static func parse(_ text: String) throws -> [TVChannel] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlaylistError.empty
        }
        guard text.utf8.count <= 1_048_576 else { throw PlaylistError.tooLarge }
        var result: [TVChannel] = []
        var nextName: String?
        var group = "Uncategorized"
        var logo: String?
        var tvgId: String?
        var lineCount = 0

        for raw in text.components(separatedBy: .newlines) {
            lineCount += 1
            if lineCount > 20_000 { throw PlaylistError.tooManyLines }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("#extinf") {
                let attrs = attributes(in: line)
                nextName = title(in: line).flatMap { $0.isEmpty ? nil : $0 }
                    ?? attrs["tvg-name"].flatMap { $0.isEmpty ? nil : $0 }
                    ?? "Unnamed"
                group = attrs["group-title"].flatMap { $0.isEmpty ? nil : $0 } ?? "Uncategorized"
                logo = attrs["tvg-logo"]
                tvgId = attrs["tvg-id"].flatMap { $0.isEmpty ? nil : $0 }
            } else if line.lowercased().hasPrefix("#extgrp:") {
                let extracted = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                group = extracted.isEmpty ? "Uncategorized" : extracted
            } else if !line.isEmpty && !line.hasPrefix("#") {
                if MediaAddress.valid(line) && result.count < 1500 {
                    let displayName = nextName ?? URLComponents(string: line)?.host ?? "Stream"
                    result.append(TVChannel(
                        name: String(displayName.prefix(200)),
                        url: line,
                        group: String(group.prefix(100)),
                        logo: logo.flatMap { MediaAddress.valid($0) ? $0 : nil },
                        tvgId: tvgId.map { String($0.prefix(150)) }
                    ))
                }
                nextName = nil
                group = "Uncategorized"
                logo = nil
                tvgId = nil
            }
        }
        return result
    }

    /// EXTINF metadata ends at the first comma outside quoted attributes.
    private static func title(in line: String) -> String? {
        var quoted = false
        for index in line.indices {
            let character = line[index]
            if character == "\"" {
                quoted.toggle()
            } else if character == "," && !quoted {
                return String(line[line.index(after: index)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func attributes(in line: String) -> [String: String] {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        var result: [String: String] = [:]
        for match in attributeRegex.matches(in: line, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else {
                continue
            }
            result[line[keyRange].lowercased()] = String(line[valueRange])
        }
        return result
    }
}
