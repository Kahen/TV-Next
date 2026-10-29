import Foundation

@main struct IntroOutroSmoke {
    static func main() {
        let digest = String(repeating: "a", count: 64)
        let suite = "tvnext-intro-outro-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = NativeIntroOutroMarkerStore(defaults: defaults)
        let empty = NativeIntroOutroMarkers()
        let intro = empty.settingIntro(90, duration: 1200)!
        let both = intro.settingOutro(1100, duration: 1200)!
        precondition(both.introTarget(current: 0, duration: 1200) == 90)
        precondition(both.introTarget(current: 100, duration: 1200) == nil)
        precondition(both.outroTarget(current: 1100, duration: 1200) == 1199)
        precondition(both.outroTarget(current: 1000, duration: 1200) == nil)
        precondition(intro.settingOutro(80, duration: 1200) == nil)
        precondition(empty.settingIntro(.nan, duration: 1200) == nil)
        precondition(empty.settingOutro(1200, duration: 1200) == nil)
        precondition(!both.isValid(duration: .infinity))
        var auto = both
        auto.automatic = true
        var state = NativeAutomaticSkipState()
        precondition(state.target(markers: auto, current: 0, duration: 1200, playing: false) == nil)
        precondition(state.target(markers: auto, current: 1, duration: 1200, playing: true) == 90)
        precondition(state.target(markers: auto, current: 0, duration: 1200, playing: true) == nil)
        state = NativeAutomaticSkipState()
        precondition(state.target(markers: auto, current: 1099, duration: 1200, playing: true) == nil)
        precondition(state.target(markers: auto, current: 1100, duration: 1200, playing: true) == 1199)
        precondition(state.target(markers: auto, current: 1101, duration: 1200, playing: true) == nil)
        state = NativeAutomaticSkipState()
        precondition(state.target(markers: auto, current: 1000, duration: 1200, playing: true) == nil)
        precondition(state.target(markers: auto, current: 1100, duration: 1200, playing: true) == nil)
        precondition(storage.save(auto, digest: digest, duration: 1200))
        precondition(NativeIntroOutroMarkerStore(defaults: defaults).markers(for: digest, duration: 1200)?.automatic == true)
        precondition(storage.save(both, digest: digest, duration: 1200))
        precondition(NativeIntroOutroMarkerStore(defaults: defaults).markers(for: digest, duration: 1200) == both)
        precondition(storage.markers(for: digest, duration: 1500) == nil)
        precondition(!storage.save(both, digest: "https://secret.invalid/movie", duration: 1200))
        storage.remove(digest: digest)
        precondition(storage.markers(for: digest, duration: 1200) == nil)
        precondition(storage.save(both, digest: digest, duration: 1200))
        storage.clear()
        precondition(defaults.object(forKey: NativeIntroOutroMarkerStore.storageKey) == nil)
        print("Native manual intro/outro marker bounds and persistence passed")
    }
}
