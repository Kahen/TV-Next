import Foundation

@main
struct DanmakuOptionsSmoke {
    static func main() {
        let name = "dev.tvnext.danmaku.smoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { fatalError("No isolated defaults") }
        defer { defaults.removePersistentDomain(forName: name) }
        precondition(DanmakuOptionsStore.load(from: defaults) == DanmakuOptions())
        var options = DanmakuOptions()
        options.enabled = false
        options.offset = -30
        options.blocked = "spoiler,剧透"
        precondition(DanmakuOptionsStore.save(options, to: defaults))
        precondition(DanmakuOptionsStore.load(from: defaults) == options)
        options.opacity = .nan
        precondition(!DanmakuOptionsStore.save(options, to: defaults))
        precondition(DanmakuOptionsStore.load(from: defaults).blocked == "spoiler,剧透")
        defaults.set(Data("{\"enabled\":true}".utf8), forKey: DanmakuOptionsStore.key)
        precondition(DanmakuOptionsStore.load(from: defaults) == DanmakuOptions())
        defaults.set(Data(repeating: 65, count: 8_193), forKey: DanmakuOptionsStore.key)
        precondition(DanmakuOptionsStore.load(from: defaults) == DanmakuOptions())
        let bounded = DanmakuOptionsStore.boundedBlocked(String(repeating: "剧", count: 2_000))
        precondition(bounded.utf8.count == 4_095)
        precondition(!bounded.contains("�"))
        // Preserve complete user-perceived characters, not merely valid UTF-8 scalars.
        let combined = String(repeating: "a", count: 4_094) + "e\u{301}" + "z"
        precondition(DanmakuOptionsStore.boundedBlocked(combined) == String(repeating: "a", count: 4_094))
        let family = "👨‍👩‍👧‍👦"
        let emojiInput = String(repeating: "a", count: 4_090) + family + "tail"
        precondition(DanmakuOptionsStore.boundedBlocked(emojiInput) == String(repeating: "a", count: 4_090))
        let exact = String(repeating: "a", count: 4_092) + "😀"
        precondition(DanmakuOptionsStore.boundedBlocked(exact) == exact)
        precondition(DanmakuOptionsStore.boundedBlocked("hello,剧透") == "hello,剧透")
        DanmakuOptionsStore.clear(from: defaults)
        precondition(defaults.data(forKey: DanmakuOptionsStore.key) == nil)
        print("Native danmaku preferences smoke passed")
    }
}
