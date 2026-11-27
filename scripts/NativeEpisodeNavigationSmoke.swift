import Foundation

@main
struct EpisodeNavigationSmoke {
    static func main() {
        func check(_ actual: Int?, _ expected: Int?, _ name: String) {
            precondition(actual == expected, "\(name): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
        let flags = [true, false, true, false, true]
        check(NativeEpisodeNavigation.adjacent(to: 0, playable: flags, direction: 1), 2, "skip unavailable forward")
        check(NativeEpisodeNavigation.adjacent(to: 4, playable: flags, direction: -1), 2, "skip unavailable backward")
        check(NativeEpisodeNavigation.adjacent(to: 4, playable: flags, direction: 1), nil, "end of line")
        check(NativeEpisodeNavigation.adjacent(to: 0, playable: flags, direction: -1), nil, "start of line")
        check(NativeEpisodeNavigation.adjacent(to: nil, playable: flags, direction: 1), nil, "no played episode")
        check(NativeEpisodeNavigation.adjacent(to: 10, playable: flags, direction: -1), nil, "invalid index")
        check(NativeEpisodeNavigation.adjacent(to: 0, playable: flags, direction: 0), nil, "invalid direction")
        check(NativeEpisodeNavigation.adjacent(to: 0, playable: [], direction: 1), nil, "empty line")
        check(NativeEpisodeNavigation.adjacent(to: 1, playable: [false,false,false], direction: 1), nil, "all unavailable")
        print("Episode navigation: 9/9 checks passed")
    }
}
