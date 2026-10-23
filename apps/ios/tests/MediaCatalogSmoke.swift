import Foundation

@main
struct MediaCatalogSmoke {
    static func main() throws {
        let text = try String(contentsOfFile: "../../fixtures/p2-fongmi-result.json", encoding: .utf8)
        let catalog = try OfflineMediaParser.parse(text)
        precondition(catalog.categories.count == 2)
        precondition(catalog.videos.count == 3)
        precondition(catalog.category("movie").count == 2)
        precondition(catalog.search("FIXTURE").count == 2)
        precondition(catalog.search("not-present").isEmpty)
        let movie = catalog.videos[0]
        precondition(movie.id == "film-1" && movie.name == "Fixture Movie")
        precondition(movie.lines.count == 2)
        precondition(movie.lines[0].episodes.map(\.name) == ["Episode 1", "Episode 2"])
        precondition(movie.lines[0].episodes[1].directURL == "https://example.org/movie2.m3u8")
        precondition(movie.lines[1].episodes[0].directURL == nil)
        precondition(catalog.videos[2].lines[0].episodes[0].directURL == nil)

        func rejects(_ text: String, _ expected: OfflineMediaError) {
            do {
                _ = try OfflineMediaParser.parse(text)
                fatalError("Malformed media JSON was accepted")
            } catch let error as OfflineMediaError {
                precondition(error == expected, "Unexpected rejection \(error)")
            } catch {
                fatalError("Unexpected parser failure \(error)")
            }
        }
        rejects(" ", .empty)
        rejects("{", .invalidJSON)
        rejects("[]", .invalidRoot)
        rejects("{}", .invalidCollections)
        rejects(#"{"class":null}"#, .invalidCollections)
        rejects(#"{"list":{}}"#, .invalidCollections)
        rejects(String(repeating: "é", count: 524_289), .tooLarge)
        let duplicate = #"{"list":[{"vod_id":"x","vod_name":"first"},{"vod_id":"x","vod_name":"second"}]}"#
        let deduplicated = try OfflineMediaParser.parse(duplicate)
        precondition(deduplicated.videos.count == 1)
        print("TV-Next offline MediaProvider golden smoke passed")
    }
}
