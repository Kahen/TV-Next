import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A bounded, device-reported DLNA position snapshot, not a local AVPlayer clock.
struct NativeDLNAPosition: Equatable {
    let seconds: Int
    let durationSeconds: Int?

    var localizedLabel: String {
        let elapsed = Self.clock(seconds)
        return durationSeconds.map { "\(elapsed) / \(Self.clock($0))" } ?? elapsed
    }

    private static func clock(_ value: Int) -> String {
        String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}

extension NativeDLNA {
    static func queryPosition(endpoint: URL) async throws -> NativeDLNAPosition {
        let approved = try rendererURL(endpoint.absoluteString)
        let request = try request(.getPositionInfo, endpoint: approved)
        let (data, response) = try await NativeDLNABoundedTransport.load(request, maxBytes: maxResponseBytes)
        return try parsePositionResponse(data, response: response)
    }

    static func parsePositionResponse(_ data: Data, response: URLResponse) throws -> NativeDLNAPosition {
        try validate(data, response: response, action: .getPositionInfo)
        return try NativeDLNAPositionParser.parse(data)
    }
}

/// Only direct, unqualified or AVTransport-namespaced fields are trusted.
/// Missing/ambiguous position never silently becomes zero.
private final class NativeDLNAPositionParser: NSObject, XMLParserDelegate {
    private let envelope = "http://schemas.xmlsoap.org/soap/envelope/"
    private var stack: [(name: String, namespace: String)] = []
    private var values: [String: String] = [:]
    private var collecting: String?
    private var text = ""
    private var invalid = false

    static func parse(_ data: Data) throws -> NativeDLNAPosition {
        let collector = NativeDLNAPositionParser()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !collector.invalid, collector.stack.isEmpty,
              let relative = collector.values["RelTime"],
              let duration = collector.values["TrackDuration"],
              let seconds = parseClock(relative) else { throw NativeDLNAError.invalidResponse }
        let total: Int?
        if duration == "NOT_IMPLEMENTED" {
            total = nil
        } else {
            guard let parsed = parseClock(duration), seconds <= parsed else {
                throw NativeDLNAError.invalidResponse
            }
            total = parsed
        }
        return NativeDLNAPosition(seconds: seconds, durationSeconds: total)
    }

    private static func parseClock(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, (1...2).contains(parts[0].count),
              parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0 >= "0" && $0 <= "9" } }),
              let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Int(parts[2]),
              hours <= 99, minutes < 60, seconds < 60 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let ns = namespaceURI ?? ""
        if collecting != nil { invalid = true }
        if elementName == "RelTime" || elementName == "TrackDuration" {
            let correctPath = stack.count == 3 &&
                stack[0].name == "Envelope" && stack[0].namespace == envelope &&
                stack[1].name == "Body" && stack[1].namespace == envelope &&
                stack[2].name == "GetPositionInfoResponse" &&
                stack[2].namespace == NativeDLNA.service
            if !correctPath || (ns != "" && ns != NativeDLNA.service) ||
                values[elementName] != nil || collecting != nil {
                invalid = true
            } else {
                collecting = elementName
                text = ""
            }
        }
        stack.append((elementName, ns))
    }

    private func append(_ fragment: String) {
        guard collecting != nil else { return }
        // Check the fragment before concatenating to avoid retaining attacker-sized values.
        if fragment.utf8.count > 32 || text.utf8.count > 32 - fragment.utf8.count {
            invalid = true
            return
        }
        text += fragment
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { append(string) }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard collecting != nil else { return }
        guard let string = String(data: CDATABlock, encoding: .utf8) else {
            invalid = true
            return
        }
        append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if collecting == elementName && stack.count == 4 {
            values[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            collecting = nil
            text = ""
        }
        guard let last = stack.popLast(), last.name == elementName,
              last.namespace == (namespaceURI ?? "") else { invalid = true; return }
    }
}
