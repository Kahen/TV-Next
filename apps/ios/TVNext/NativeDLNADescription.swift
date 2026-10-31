import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Opt-in import of a single AVTransport:1 control URL from a LAN UPnP description.
/// This deliberately does not perform SSDP discovery or trust XML URLBase.
enum NativeDLNADescription {
    static let deviceNamespace = "urn:schemas-upnp-org:device-1-0"

    static func location(_ text: String) throws -> URL {
        try NativeDLNA.rendererURL(text)
    }

    static func load(_ text: String) async throws -> URL {
        let approved = try location(text)
        var request = URLRequest(url: approved, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.setValue("application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await NativeDLNABoundedTransport.load(request, maxBytes: NativeDLNA.maxResponseBytes)
        guard let http = response as? HTTPURLResponse else { throw NativeDLNAError.invalidDescription }
        guard http.statusCode == 200 else { throw NativeDLNAError.httpStatus(http.statusCode) }
        return try parse(data, location: approved)
    }

    static func parse(_ data: Data, location: URL) throws -> URL {
        let approved = try self.location(location.absoluteString)
        guard !data.isEmpty, data.count <= NativeDLNA.maxResponseBytes,
              let body = String(data: data, encoding: .utf8),
              !body.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !body.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw NativeDLNAError.invalidDescription
        }
        let collector = DescriptionCollector()
        let parser = XMLParser(data: Data(body.utf8))
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        guard parser.parse(), !collector.invalid, collector.stack.isEmpty,
              let control = collector.control else { throw NativeDLNAError.invalidDescription }
        return try resolve(control, from: approved)
    }

    static func resolve(_ raw: String, from location: URL) throws -> URL {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 256,
              !value.contains("%"), !value.contains("?"), !value.contains("#"),
              !value.contains("\\"), !value.contains(" "), !value.hasPrefix("//"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0 == "." || $0 == ".." }),
              let absolute = URL(string: value, relativeTo: location)?.absoluteURL,
              let checked = try? NativeDLNA.rendererURL(absolute.absoluteString),
              checked.host == location.host, checked.port == location.port,
              checked.scheme == location.scheme else { throw NativeDLNAError.invalidDescription }
        return checked
    }
}

private final class DescriptionCollector: NSObject, XMLParserDelegate {
    private let namespace = NativeDLNADescription.deviceNamespace
    private let fields = ["serviceType", "controlURL"]
    private(set) var stack: [String] = []
    private(set) var control: String?
    private(set) var invalid = false
    private var serviceFields: [String: String] = [:]
    private var collecting: String?
    private var text = ""

    private func correctNamespace(_ value: String?) -> Bool { value == namespace }
    private func isService(_ names: [String]) -> Bool {
        names == ["root", "device", "serviceList", "service"]
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if collecting != nil { invalid = true }
        if stack.isEmpty {
            if name != "root" || !correctNamespace(namespaceURI) { invalid = true }
        } else if ["device", "serviceList", "service", "serviceType", "controlURL"].contains(name),
                  !correctNamespace(namespaceURI) {
            invalid = true
        }
        stack.append(name)
        if isService(stack) { serviceFields = [:] }
        if fields.contains(name) && isService(Array(stack.dropLast())) {
            if serviceFields[name] != nil || collecting != nil { invalid = true }
            collecting = name
            text = ""
        }
    }

    private func append(_ fragment: String) {
        guard let collecting else { return }
        let limit = collecting == "controlURL" ? 256 : 128
        guard fragment.utf8.count <= limit, text.utf8.count <= limit - fragment.utf8.count else {
            invalid = true
            return
        }
        text += fragment
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { append(string) }
    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        guard collecting != nil else { return }
        guard let fragment = String(data: data, encoding: .utf8) else { invalid = true; return }
        append(fragment)
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard stack.last == name else { invalid = true; return }
        if collecting == name && isService(Array(stack.dropLast())) {
            serviceFields[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            collecting = nil
            text = ""
        }
        if isService(stack) && serviceFields["serviceType"] == NativeDLNA.service {
            guard control == nil, let value = serviceFields["controlURL"], !value.isEmpty else {
                invalid = true
                stack.removeLast()
                return
            }
            control = value
        }
        stack.removeLast()
    }
}
