import Foundation

/// Normalized FongMi milliseconds. These are ephemeral source hints, never
/// user-created markers or an instruction to seek automatically.
struct NativeProviderSkipSegment: Decodable, Hashable {
    let type: String
    let startMs: Int64
    let endMs: Int64?

    var isValid: Bool {
        guard ["opening", "middle", "ending"].contains(type),
              (0...604_800_000).contains(startMs) else { return false }
        guard let endMs else { return type == "ending" && startMs > 0 }
        return endMs > startMs && endMs <= 604_800_000
    }

    var label: String {
        switch type {
        case "opening": return "跳过来源片头"
        case "middle": return "跳过来源片段"
        default: return "跳过来源片尾"
        }
    }

    func target(current: Double, duration: Double) -> Double? {
        guard isValid, current.isFinite, duration.isFinite,
              duration > 0, duration < 604_800, current >= 0, current < duration else { return nil }
        let start = Double(startMs) / 1000
        let end = endMs.map { Double($0) / 1000 } ?? duration
        guard start < duration, end <= duration, current >= start, current < end else { return nil }
        return end
    }

    static func normalized(_ input: [NativeProviderSkipSegment]) -> [NativeProviderSkipSegment] {
        var seen = Set<NativeProviderSkipSegment>()
        return Array(input.prefix(128).filter { $0.isValid && seen.insert($0).inserted }.prefix(32))
    }
}

/// A malformed optional hint must not prevent the actual media from loading.
/// Inspect at most 128 members and retain at most 32 unique valid segments.
struct NativeProviderSkipSegments: Decodable {
    let values: [NativeProviderSkipSegment]

    init(from decoder: Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else { values = []; return }
        var parsed: [NativeProviderSkipSegment] = []
        for _ in 0..<128 {
            if container.isAtEnd { break }
            let child = try container.superDecoder()
            if let segment = try? NativeProviderSkipSegment(from: child) { parsed.append(segment) }
        }
        values = NativeProviderSkipSegment.normalized(parsed)
    }
}
