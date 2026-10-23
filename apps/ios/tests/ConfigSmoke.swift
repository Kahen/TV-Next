import Foundation

@main
struct ConfigSmoke {
    static func main() throws {
        let fixture = """
        {
          "spider": "https://example.org/fixture.jar",
          "sites": [
            {"key":"demo","name":"Sample","type":3,"searchable":0,"hide":1,
             "api":"csp_Example","categories":["Drama","Movies"]},
            {"key":"demo","name":"Duplicate"},
            {"key":"other","name":"Second"}
          ],
          "lives":[{"name":"News"}]
        }
        """
        let result = try OfflineConfigParser.parse(fixture)
        precondition(result.sites.count == 2)
        precondition(result.sites[0].key == "demo")
        precondition(result.sites[0].name == "Sample")
        precondition(result.sites[0].type == 3)
        precondition(!result.sites[0].searchable && result.sites[0].hidden)
        precondition(result.sites[0].categories == ["Drama", "Movies"])
        precondition(result.liveSourceCount == 1 && result.spiderDeclared)
        let empty = try OfflineConfigParser.parse("{}")
        precondition(empty.sites.isEmpty)

        func mustReject(_ text: String, _ expected: OfflineConfigError) {
            do {
                _ = try OfflineConfigParser.parse(text)
                fatalError("Unexpectedly accepted invalid config")
            } catch let error as OfflineConfigError {
                precondition(error == expected, "Unexpected rejection: \(error)")
            } catch {
                fatalError("Unexpected error: \(error)")
            }
        }

        mustReject(" ", .empty)
        mustReject("{", .invalidJSON)
        mustReject("[]", .invalidRoot)
        mustReject("{\"sites\":{}}", .invalidSites)
        mustReject("{\"lives\":null}", .invalidLives)
        mustReject(String(repeating: "é", count: 524_289), .tooLarge)

        let many = (0..<1002).map { "{\"key\":\"s" + String($0) + "\",\"name\":\"Sample\"}" }.joined(separator: ",")
        let bounded = try OfflineConfigParser.parse("{\"sites\":[" + many + "]}")
        precondition(bounded.sites.count == 1000)
        precondition(!bounded.warnings.isEmpty)
        let noCode = try OfflineConfigParser.parse("{\"spider\":\"provider.jar\",\"sites\":[{\"key\":\"a\",\"api\":\"csp_Demo\"}]}")
        precondition(noCode.sites.count == 1 && noCode.spiderDeclared)
        print("TV-Next offline JSON config parser smoke tests passed")
    }
}
