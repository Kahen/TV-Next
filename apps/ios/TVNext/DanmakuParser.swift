import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct DanmakuComment: Equatable {
    let time: Double
    let mode: Int
    let size: Double
    let color: UInt32
    let text: String
}

enum DanmakuParser {
    static func parse(_ text: String) throws -> [DanmakuComment] {
        guard text.utf8.count <= 2_097_152 else { throw DanmakuError.invalid }
        var comments: [DanmakuComment] = []
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            guard text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
                  text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw DanmakuError.invalid }
            let delegate = SafeDanmakuXML()
            let parser = XMLParser(data: Data(text.utf8))
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), !delegate.exceeded else { throw DanmakuError.invalid }
            comments = delegate.comments
        } else {
            let root = try JSONSerialization.jsonObject(with: Data(text.utf8))
            let rows = (root as? [[String: Any]]) ?? (root as? [String: Any])?["comments"] as? [[String: Any]]
            guard let rows, rows.count <= 20_000 else { throw DanmakuError.invalid }
            comments = rows.compactMap { row in
                guard let p = row["p"] as? String, let message = (row["m"] ?? row["text"]) as? String else { return nil }
                return comment(p, message, dandan: true)
            }
        }
        return comments.sorted { $0.time < $1.time }
    }
    fileprivate static func comment(_ p: String, _ message: String, dandan: Bool = false) -> DanmakuComment? {
        let parts = p.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= (dandan ? 3 : 4), let time = Double(parts[0]), time.isFinite, time >= 0, time <= 604800,
              let mode = Int(parts[1]), [1,4,5,6].contains(mode), let color = UInt32(parts[dandan ? 2 : 3]), color <= 0xffffff,
              let size = dandan ? 25.0 : Double(parts[2]), size.isFinite else { return nil }
        let value = String(message.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }.map(String.init).joined().trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !value.isEmpty else { return nil }
        return DanmakuComment(time: time, mode: mode, size: max(12,min(48,size)), color: color, text: value)
    }
}
private final class SafeDanmakuXML: NSObject, XMLParserDelegate {
    var comments: [DanmakuComment] = []
    var exceeded = false
    private var parameter: String?
    private var text = ""
    private var count = 0
    private var depth = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        depth += 1
        if depth > 20 { exceeded = true; parser.abortParsing(); return }
        if name == "d" {
            count += 1
            if count > 20_000 { exceeded = true; parser.abortParsing(); return }
            parameter = attributes["p"]; text = ""
        }
    }
    func parser(_ parser: XMLParser, foundCharacters value: String) {
        if parameter != nil && text.count < 1000 { text += String(value.prefix(1000 - text.count)) }
    }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { self.parser(parser, foundCharacters: String(decoding: data, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "d", let parameter {
            if let comment = DanmakuParser.comment(parameter,text) { comments.append(comment) }
            self.parameter = nil; text = ""
        }
        depth -= 1
    }
}
enum DanmakuError: LocalizedError {
    case invalid
    var errorDescription: String? { "弹幕格式无效、超出 2 MiB / 20000 条限制，或包含禁用的 XML 内容。" }
}
