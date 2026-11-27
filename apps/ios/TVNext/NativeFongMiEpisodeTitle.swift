import Foundation

enum NativeFongMiEpisodeTitle {
    /// Provider labels are display-only: never append media URLs or control characters.
    static func compose(series: String, episode: String) -> String {
        let safeSeries = clean(series)
        let safeEpisode = clean(episode)
        guard !safeEpisode.isEmpty, safeEpisode != safeSeries else { return safeSeries }
        guard !safeSeries.isEmpty else { return safeEpisode }
        return safeSeries + " · " + safeEpisode
    }

    private static func clean(_ input: String) -> String {
        let visible = input.unicodeScalars.filter {
            switch $0.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return false
            default: return true
            }
        }
        let value = String(String.UnicodeScalarView(visible)).trimmingCharacters(in: .whitespacesAndNewlines)
        // Avoid propagating opaque provider playback URLs into system Now Playing metadata.
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return ""
        }
        return String(value.prefix(120))
    }
}
