import Foundation

/// Normalized FongMi milliseconds. These are ephemeral source hints, never
/// user-created markers. Automatic use requires explicit playback-local consent.
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
        var result: [NativeProviderSkipSegment] = []
        for segment in input.prefix(128) {
            guard segment.isValid, seen.insert(segment).inserted else { continue }
            result.append(segment)
            if result.count == 32 { break }
        }
        return result
    }
}

/// A malformed optional hint must not prevent the actual media from loading.
/// Inspect at most 128 members and retain at most 32 unique valid segments.
struct NativeProviderSkipSegments: Decodable {
    let values: [NativeProviderSkipSegment]

    init(from decoder: Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else { values = []; return }
        var parsed: [NativeProviderSkipSegment] = []
        var seen = Set<NativeProviderSkipSegment>()
        for _ in 0..<128 {
            if container.isAtEnd || parsed.count == 32 { break }
            let child = try container.superDecoder()
            guard let segment = try? NativeProviderSkipSegment(from: child),
                  segment.isValid, seen.insert(segment).inserted else { continue }
            parsed.append(segment)
        }
        values = parsed
    }
}

/// One automatic attempt per source segment in this playback. Provider order
/// breaks ties, matching VodSkipPolicy; explicit seeks and discontinuities
/// suppress the entered range so seeking back does not trap a viewer in a loop.
/// The caller owns consent, item/generation checks and in-flight seek exclusion.
struct NativeAutomaticProviderSkipState {
    private var consumed = Set<NativeProviderSkipSegment>()
    private var previousTime: Double?

    mutating func target(segments: [NativeProviderSkipSegment], current: Double,
                         duration: Double, playing: Bool) -> Double? {
        guard current.isFinite, duration.isFinite, duration > 0, duration < 604_800,
              current >= 0, current < duration else { return nil }
        let previous = previousTime
        previousTime = current
        if let previous, current < previous - 0.25 || current - previous > 3 {
            recordExplicitSeek(to: current, segments: segments, duration: duration)
            return nil
        }
        guard playing else { return nil }
        for segment in segments.prefix(32) where !consumed.contains(segment) {
            guard let target = segment.target(current: current, duration: duration) else { continue }
            consumed.insert(segment)
            // A completed automatic seek is not a user discontinuity. This also
            // permits the next overlapping/adjacent range in provider order.
            previousTime = target
            return target
        }
        return nil
    }

    // Rebase the clock after an opt-in change without consuming any source range.
    // Time elapsed while disabled must not be mistaken for a manual seek.
    mutating func rebaseClock(to time: Double, duration: Double) {
        guard time.isFinite, duration.isFinite, duration > 0,
              duration < 604_800, time >= 0, time < duration else { return }
        previousTime = time
    }

    mutating func recordExplicitSeek(to time: Double, segments: [NativeProviderSkipSegment], duration: Double) {
        guard time.isFinite, duration.isFinite, time >= 0, time <= duration else { return }
        previousTime = time
        for segment in segments.prefix(32) where segment.target(current: time, duration: duration) != nil {
            consumed.insert(segment)
        }
    }
}
