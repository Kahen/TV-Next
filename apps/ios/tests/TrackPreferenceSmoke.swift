import Foundation

@main
struct TrackPreferenceSmoke {
    static func main() {
        typealias Option = (name: String, languageTag: String?)
        let preferred: Option = ("English", "en")
        let filler: Option = ("Other", "fr")
        func choose(_ options: [Option], _ name: String = "English", _ language: String? = "en") -> Int? {
            NativeTrackPreferencePolicy.uniqueVisibleIndex(in: options, name: name, languageTag: language)
        }
        precondition(choose([preferred]) == 0)
        precondition(choose([filler, preferred]) == 1)
        precondition(choose([preferred, preferred]) == nil)
        precondition(choose(Array(repeating: filler, count: 15) + [preferred]) == 15)
        precondition(choose(Array(repeating: filler, count: 16) + [preferred]) == nil)
        precondition(choose([preferred] + Array(repeating: filler, count: 15) + [preferred]) == nil)
        precondition(choose([preferred, ("English", "ja")]) == 0)
        precondition(choose([preferred], "English", nil) == nil)
        precondition(choose([preferred], "english") == nil)
        precondition(choose([preferred], "") == nil)
        precondition(choose([preferred], String(repeating: "x", count: 81)) == nil)
        let eighty = String(repeating: "x", count: 80)
        precondition(choose([(eighty, nil)], eighty, nil) == 0)
        let sixtyFour = String(repeating: "l", count: 64)
        precondition(choose([("English", sixtyFour)], "English", sixtyFour) == 0)
        precondition(choose([("English", sixtyFour + "x")], "English", sixtyFour + "x") == nil)
        precondition(choose([]) == nil)
        print("Native track preference identity smoke passed")
    }
}
