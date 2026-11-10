import Foundation

@main struct ProviderSkipSegmentsSmoke {
    private struct Fixture: Decodable {
        struct Position: Decodable { let seconds: Double; let duration: Double; let type: String?; let target: Double? }
        let expected: NativeProviderSkipSegments
        let positions: [Position]
    }

    static func main() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            URL(fileURLWithPath: "../../fixtures/fongmi-provider-skips-golden.json")))
        for position in fixture.positions {
            let active = fixture.expected.values.first { $0.target(current: position.seconds, duration: position.duration) != nil }
            precondition(active?.type == position.type)
            precondition(active?.target(current: position.seconds, duration: position.duration) == position.target)
        }
        let opening = fixture.expected.values[0]
        for current in [Double.nan, .infinity, -.infinity] {
            precondition(opening.target(current: current, duration: 1200) == nil)
        }
        for duration in [Double.nan, .infinity, 0, -1, 604800] {
            precondition(opening.target(current: 0, duration: duration) == nil)
        }
        let malformed = Data(#"[null,4,{}, {"type":"middle","startMs":1.5,"endMs":10}, {"type":"opening","startMs":0,"endMs":5000}, {"type":"opening","startMs":0,"endMs":5000}]"#.utf8)
        let parsed = try JSONDecoder().decode(NativeProviderSkipSegments.self, from: malformed)
        precondition(parsed.values == [NativeProviderSkipSegment(type: "opening", startMs: 0, endMs: 5000)])
        let bounded = try JSONDecoder().decode(NativeProviderSkipSegments.self, from:
            Data(("[" + (0..<200).map { "{\"type\":\"middle\",\"startMs\":\($0),\"endMs\":\($0 + 1)}" }.joined(separator: ",") + "]").utf8))
        precondition(bounded.values.count == 32)
        let late = "[" + Array(repeating: "null", count: 128).joined(separator: ",") + ",{\"type\":\"opening\",\"startMs\":0,\"endMs\":1}]"
        let clipped = try JSONDecoder().decode(NativeProviderSkipSegments.self, from: Data(late.utf8))
        precondition(clipped.values.isEmpty)
        let intro = NativeProviderSkipSegment(type: "opening", startMs: 0, endMs: 5000)
        let middle = NativeProviderSkipSegment(type: "middle", startMs: 5000, endMs: 10000)
        var automatic = NativeAutomaticProviderSkipState()
        precondition(automatic.target(segments: [intro, middle], current: 0, duration: 120, playing: false) == nil)
        precondition(automatic.target(segments: [intro, middle], current: 0.5, duration: 120, playing: true) == 5)
        precondition(automatic.target(segments: [intro, middle], current: 5, duration: 120, playing: true) == 10)
        precondition(automatic.target(segments: [intro, middle], current: 1, duration: 120, playing: true) == nil)
        precondition(automatic.target(segments: [intro, middle], current: 2, duration: 120, playing: true) == nil)
        automatic = NativeAutomaticProviderSkipState()
        automatic.recordExplicitSeek(to: 6, segments: [middle], duration: 120)
        precondition(automatic.target(segments: [middle], current: 6, duration: 120, playing: true) == nil)
        print("Native provider skip millisecond bounds, order and shared targets passed")
    }
}
