import Foundation

struct CaptionCue: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

enum CaptionError: LocalizedError {
    case empty
    case tooLarge
    case invalidEncoding
    case invalidTimeline

    var errorDescription: String? {
        switch self {
        case .empty: return "字幕文件为空。"
        case .tooLarge: return "字幕文件超过 1 MiB。"
        case .invalidEncoding: return "字幕必须是 UTF-8 编码的 SRT 或 WebVTT。"
        case .invalidTimeline: return "未识别有效的字幕时间轴；仅支持基础 SRT / WebVTT。"
        }
    }
}

/// Lightweight text-only SRT / WebVTT parser. Does not execute markup or load URLs.
/// Rich styling, ASS and WebVTT cue positioning are intentionally out of scope.
enum CaptionParser {
    private static let timing = try! NSRegularExpression(
        pattern: #"^(\d{2,3}:\d{2}:\d{2}[.,]\d{3}|\d{2}:\d{2}[.,]\d{3})\s+-->\s+(\d{2,3}:\d{2}:\d{2}[.,]\d{3}|\d{2}:\d{2}[.,]\d{3})(?:\s+.*)?$"#
    )
    private static let tags = try! NSRegularExpression(pattern: #"<[^>]*>"#)

    static func parse(_ data: Data) throws -> [CaptionCue] {
        guard !data.isEmpty else { throw CaptionError.empty }
        guard data.count <= 1_048_576 else { throw CaptionError.tooLarge }
        guard var input = String(data: data, encoding: .utf8) else { throw CaptionError.invalidEncoding }

        input = input.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var result: [CaptionCue] = []
        let blocks = input.components(separatedBy: "\n\n")
        for block in blocks.prefix(12_000) {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !lines.isEmpty else { continue }
            if lines[0].hasPrefix("WEBVTT") || lines[0].hasPrefix("NOTE") ||
                lines[0] == "STYLE" || lines[0] == "REGION" { continue }
            let timingIndex = lines.firstIndex(where: { $0.contains("-->") })
            guard let index = timingIndex, index <= 1, lines.count > index + 1 else { continue }

            let range = NSRange(lines[index].startIndex..<lines[index].endIndex, in: lines[index])
            guard let match = timing.firstMatch(in: lines[index], range: range),
                  let startRange = Range(match.range(at: 1), in: lines[index]),
                  let endRange = Range(match.range(at: 2), in: lines[index]),
                  let start = seconds(String(lines[index][startRange])),
                  let end = seconds(String(lines[index][endRange])),
                  end > start else { continue }

            let caption = lines.dropFirst(index + 1).joined(separator: "\n")
            let rangeForTags = NSRange(caption.startIndex..<caption.endIndex, in: caption)
            let stripped = tags.stringByReplacingMatches(
                in: caption, range: rangeForTags, withTemplate: ""
            ).replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.isEmpty { continue }
            result.append(CaptionCue(start: start, end: end, text: String(stripped.prefix(2_000))))
            if result.count >= 5_000 { break }
        }
        guard !result.isEmpty else { throw CaptionError.invalidTimeline }
        return result.sorted { $0.start < $1.start }
    }

    /// Positive offset delays text relative to media time; negative advances it.
    static func activeText(_ cues: [CaptionCue], at time: TimeInterval,
                           offset: TimeInterval = 0) -> String {
        guard time.isFinite, offset.isFinite, offset >= -10, offset <= 10 else { return "" }
        let subtitleTime = time - offset
        return cues.first(where: { subtitleTime >= $0.start && subtitleTime < $0.end })?.text ?? ""
    }

    private static func seconds(_ value: String) -> TimeInterval? {
        let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let hour = parts.count == 3 ? Int(parts[0]) : 0
        let minute = Int(parts[parts.count - 2])
        let second = Double(parts[parts.count - 1])
        guard let h = hour, let m = minute, let s = second,
              h >= 0, m >= 0, m < 60, s >= 0, s < 60 else { return nil }
        return Double(h * 3600 + m * 60) + s
    }
}
