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

        print("TV-Next native M3U parser smoke test passed")
    }
}
