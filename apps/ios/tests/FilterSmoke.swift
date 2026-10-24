import Foundation

@main struct FilterSmoke {
    struct Fixture: Decodable { let expected: [String:[NativeSiteFilter]];let initial: [String:String] }
    static func main() throws {
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:"../../fixtures/fongmi-filters-golden.json")))
        precondition(NativeSiteFilter.defaults(fixture.expected["movie"]!)==fixture.initial)
        precondition(NativeSiteFilter.defaults(fixture.expected["series"]!)==["sort":""])
        precondition(fixture.expected["movie"]![0].value.map(\.v)==["","cn","us"])
        print("Native/JVM original subscription filters contract passed")
    }
}
