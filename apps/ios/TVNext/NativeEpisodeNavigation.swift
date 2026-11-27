import Foundation

/// Navigation stays within the selected source line and skips unavailable episodes.
enum NativeEpisodeNavigation {
    static func adjacent(to current: Int?, playable: [Bool], direction: Int) -> Int? {
        guard direction == -1 || direction == 1, let current,
              playable.indices.contains(current) else { return nil }
        var candidate = current + direction
        while playable.indices.contains(candidate) {
            if playable[candidate] { return candidate }
            candidate += direction
        }
        return nil
    }
}
