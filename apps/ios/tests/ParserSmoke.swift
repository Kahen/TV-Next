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

        // Some authorized IPTV exports use single-quoted EXTINF metadata.
        // A comma inside either quote style must not become the channel title.
        let quoted = try M3UParser.parse("""
        #EXTM3U
        #EXTINF:-1 group-title='Sports, HD' tvg-id='station-1' tvg-logo='https://example.org/logo.png',Match One
        https://example.org/one.m3u8
        #EXTINF:-1 group-title="News, Live" tvg-name='Fallback Station'
        https://example.org/two.m3u8
        #EXTINF:-1 group-title='Invalid',Bad
        javascript:alert(1)
        """)
        precondition(quoted.count == 2)
        precondition(quoted[0].name == "Match One")
        precondition(quoted[0].group == "Sports, HD")
        precondition(quoted[0].tvgId == "station-1")
        precondition(quoted[0].logo == "https://example.org/logo.png")
        precondition(quoted[1].name == "Fallback Station")
        precondition(quoted[1].group == "News, Live")

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
        // The same synthetic fixture is asserted in Kotlin API tests.
        let fixture = try String(contentsOfFile: "../../fixtures/p1-m3u-golden.m3u", encoding: .utf8)
        let expectedData = try Data(contentsOf: URL(fileURLWithPath: "../../fixtures/p1-m3u-golden.json"))
        let expected = try JSONDecoder().decode([TVChannel].self, from: expectedData)
        let actual = try M3UParser.parse(fixture)
        precondition(actual.count == expected.count, "Golden M3U channel count differs")
        for (found, wanted) in zip(actual, expected) {
            precondition(found.name == wanted.name, "Golden M3U name differs")
            precondition(found.url == wanted.url, "Golden M3U URL differs")
            precondition(found.group == wanted.group, "Golden M3U group differs")
            precondition(found.logo == wanted.logo, "Golden M3U logo differs")
            precondition(found.tvgId == wanted.tvgId, "Golden M3U tvg-id differs")
        }
        print("TV-Next native M3U import/export and golden parity tests passed")
    }
}
