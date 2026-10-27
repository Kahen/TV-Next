import Foundation

@main struct ActionSmoke {
    struct Fixture: Decodable {
        struct Case: Decodable {
            let name: String
            let body: RawValue
            let url: String?
            let message: String?
            let warning: Bool
        }
        let cases: [Case]
    }
    struct RawValue: Decodable {
        let raw: Data
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let object = try container.decode([String: JSONValue].self)
            raw = try JSONEncoder().encode(object)
        }
    }
    indirect enum JSONValue: Codable {
        case text(String), object([String: JSONValue]), array([JSONValue]), null, bool(Bool), number(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null }
            else if let v = try? c.decode(String.self) { self = .text(v) }
            else if let v = try? c.decode(Bool.self) { self = .bool(v) }
            else if let v = try? c.decode(Double.self) { self = .number(v) }
            else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
            else { self = .array(try c.decode([JSONValue].self)) }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text(let v): try c.encode(v)
            case .object(let v): try c.encode(v)
            case .array(let v): try c.encode(v)
            case .null: try c.encodeNil()
            case .bool(let v): try c.encode(v)
            case .number(let v): try c.encode(v)
            }
        }
    }
    static func main() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: "../../fixtures/fongmi-action-web-golden.json")))
        for item in fixture.cases {
            let result = try JSONDecoder().decode(NativeSubscriptionAction.self, from: item.body.raw)
            precondition(result.link?.absoluteString == item.url, "URL mismatch: \(item.name)")
            precondition(result.message == item.message, "Message mismatch: \(item.name)")
            precondition(result.unsupported || result.limitedBrowserFeatures == item.warning, "Warning mismatch: \(item.name)")
        }
        print("Native/Web FongMi action web contract passed")
    }
}
