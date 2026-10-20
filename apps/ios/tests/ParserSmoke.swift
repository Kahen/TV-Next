import Foundation

@main
struct ParserSmoke {
    static func main() throws {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 group-title="News" tvg-id="sample",Sample Channel
        https://example.org/live.m3u8
        #EXTINF:-1,Evil Protocol
        javascript:alert(1)
        #EXTINF:-1,Embedded Credentials
        https://user:pass@example.org/video.mp4
        #EXTINF:-1,Movie
        https://example.org/movie.mp4
        """

        let channels = try M3UParser.parse(playlist)
        precondition(channels.count == 2, "Invalid streams should be rejected")
        precondition(channels[0].name == "Sample Channel")
        precondition(channels[0].group == "News")
        precondition(channels[0].tvgId == "sample")
        precondition(channels[1].name == "Movie")
        precondition(!MediaAddress.valid("javascript:alert(1)"))
        precondition(!MediaAddress.valid("https://user:secret@example.org/path"))
        precondition(!MediaAddress.valid("https://example.org/\n#EXTINF:-1"))

        do {
            _ = try M3UParser.parse(" ")
            fatalError("Empty M3U was not rejected")
        } catch PlaylistError.empty {
            // Expected.
        }

        do {
            _ = try M3UParser.parse(String(repeating: "a", count: 1_048_577))
            fatalError("Large M3U was not rejected")
        } catch PlaylistError.tooLarge {
            // Expected.
        }

        let exported = M3UEncoder.serialize(channels)
        precondition(exported.hasPrefix("#EXTM3U\n"))
        let roundTrip = try M3UParser.parse(exported)
        precondition(roundTrip.count == 2)
        precondition(roundTrip[0].group == "News")
        precondition(roundTrip[0].tvgId == "sample")
        let sanitized = TVChannel(
            name: "Line\nBreak", url: "https://example.org/stream.mp4",
            group: "TV\"Group", logo: nil, tvgId: nil
        )
        let safe = M3UEncoder.serialize([sanitized])
        precondition(!safe.contains("TV\"Group"))
        precondition(safe.contains("TV Group"))
        print("TV-Next native M3U import/export smoke tests passed")
    }
}
