import Foundation

/// Explicit, user-created boundaries. No provider inference or automatic skipping.
struct NativeIntroOutroMarkers: Codable, Equatable {
    var introEnd: Double?
    var outroStart: Double?

    func isValid(duration: Double) -> Bool {
        guard duration.isFinite, duration >= 120, duration < 604_800 else { return false }
        if let introEnd {
            guard introEnd.isFinite, introEnd >= 5,
                  introEnd <= min(600, duration / 2), introEnd <= duration - 5 else { return false }
        }
        if let outroStart {
            guard outroStart.isFinite, outroStart >= duration / 2,
                  outroStart <= duration - 5 else { return false }
        }
        if let introEnd, let outroStart, outroStart - introEnd < 5 { return false }
        return introEnd != nil || outroStart != nil
    }

    func settingIntro(_ time: Double, duration: Double) -> NativeIntroOutroMarkers? {
        let candidate = NativeIntroOutroMarkers(introEnd: time, outroStart: outroStart)
        return candidate.isValid(duration: duration) ? candidate : nil
    }

    func settingOutro(_ time: Double, duration: Double) -> NativeIntroOutroMarkers? {
        let candidate = NativeIntroOutroMarkers(introEnd: introEnd, outroStart: time)
        return candidate.isValid(duration: duration) ? candidate : nil
    }

    func introTarget(current: Double, duration: Double) -> Double? {
        guard isValid(duration: duration), let introEnd,
              current.isFinite, current >= 0, current < introEnd else { return nil }
        return introEnd
    }

    func outroTarget(current: Double, duration: Double) -> Double? {
        guard isValid(duration: duration), let outroStart,
              current.isFinite, current >= outroStart, current < duration - 1 else { return nil }
        return duration - 1
    }
}

private struct NativeIntroOutroRecord: Codable {
    let digest: String
    let markers: NativeIntroOutroMarkers
    let duration: Double
}

private struct NativeIntroOutroSnapshot: Codable {
    let version: Int
    let records: [NativeIntroOutroRecord]
}

/// A bounded, device-local preference store. Never persists media URLs or headers.
final class NativeIntroOutroMarkerStore {
    static let storageKey = "tv-next-intro-outro-v1"
    private let defaults: UserDefaults
    private var records: [NativeIntroOutroRecord] = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey), data.count <= 64_000,
              let snapshot = try? JSONDecoder().decode(NativeIntroOutroSnapshot.self, from: data),
              snapshot.version == 1 else { return }
        var seen = Set<String>()
        records = Array(snapshot.records.reversed().filter { entry in
            Self.validDigest(entry.digest) && entry.markers.isValid(duration: entry.duration)
                && seen.insert(entry.digest).inserted
        }.prefix(100).reversed())
    }

    private static func validDigest(_ digest: String) -> Bool {
        digest.count == 64 && digest.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    func markers(for digest: String, duration: Double) -> NativeIntroOutroMarkers? {
        guard Self.validDigest(digest), let entry = records.first(where: { $0.digest == digest }),
              entry.markers.isValid(duration: duration),
              abs(entry.duration - duration) <= max(2, entry.duration * 0.01) else { return nil }
        return entry.markers
    }

    @discardableResult
    func save(_ markers: NativeIntroOutroMarkers, digest: String, duration: Double) -> Bool {
        guard Self.validDigest(digest), markers.isValid(duration: duration) else { return false }
        let updated = Array((records.filter { $0.digest != digest } + [
            NativeIntroOutroRecord(digest: digest, markers: markers, duration: duration)
        ]).suffix(100))
        let snapshot = NativeIntroOutroSnapshot(version: 1, records: updated)
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= 64_000 else { return false }
        defaults.set(data, forKey: Self.storageKey)
        records = updated
        return true
    }

    func remove(digest: String) {
        records.removeAll { $0.digest == digest }
        write()
    }

    func clear() {
        records = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(NativeIntroOutroSnapshot(version: 1, records: records)),
              data.count <= 64_000 else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
