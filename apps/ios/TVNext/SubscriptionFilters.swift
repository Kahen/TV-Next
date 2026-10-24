import Foundation

struct NativeSiteFilter: Decodable,Identifiable {
    struct Value: Decodable { let n: String;let v: String }
    let key: String;let name: String;let initial: String?;let value: [Value]
    var id: String { key }
    enum CodingKeys: String,CodingKey { case key,name,value;case initial="init" }
    static func defaults(_ filters: [NativeSiteFilter]) -> [String:String] {
        Dictionary(filters.prefix(30).map { ($0.key,$0.initial ?? "") },uniquingKeysWith:{ first,_ in first })
    }
}
