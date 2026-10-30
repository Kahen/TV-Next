import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Standard UPnP AVTransport v1 states. Unknown values are never shown as verified playback.
enum NativeDLNATransportState: String, Equatable {
    case stopped = "STOPPED"
    case playing = "PLAYING"
    case pausedPlayback = "PAUSED_PLAYBACK"
    case transitioning = "TRANSITIONING"
    case noMediaPresent = "NO_MEDIA_PRESENT"
    case recording = "RECORDING"
    case pausedRecording = "PAUSED_RECORDING"

    var localizedLabel: String {
        switch self {
        case .stopped: return "已停止"
        case .playing: return "正在播放"
        case .pausedPlayback: return "已暂停"
        case .transitioning: return "正在切换"
        case .noMediaPresent: return "没有媒体"
        case .recording: return "正在录制"
        case .pausedRecording: return "录制已暂停"
        }
    }

    var canControlPlayback: Bool {
        switch self {
        case .playing, .pausedPlayback, .transitioning: return true
        default: return false
        }
    }
}

extension NativeDLNA {
    /// Read-only status query. Reuses the same private-address validation,
    /// eight-second deadline, cancellation, redirect denial and 32 KiB cap.
    static func queryState(endpoint: URL) async throws -> NativeDLNATransportState {
        let approved = try rendererURL(endpoint.absoluteString)
        let request = try request(.getTransportInfo, endpoint: approved)
        let (data, response) = try await NativeDLNABoundedTransport.load(request, maxBytes: maxResponseBytes)
        return try parseStateResponse(data, response: response)
    }

    static func parseStateResponse(_ data: Data, response: URLResponse) throws -> NativeDLNATransportState {
        try validate(data, response: response, action: .getTransportInfo)
        return try NativeDLNAStateParser.parse(data)
    }
}

/// Extract exactly one direct CurrentTransportState child from a validated SOAP
/// GetTransportInfoResponse. Never infer state from nested/foreign XML.
private final class NativeDLNAStateParser: NSObject, XMLParserDelegate {
    private let envelope = "http://schemas.xmlsoap.org/soap/envelope/"
    private var stack: [(name: String, namespace: String)] = []
    private var state: NativeDLNATransportState?
    private var raw = ""
    private var collecting = false
    private var occurrences = 0
    private var invalid = false

    static func parse(_ data: Data) throws -> NativeDLNATransportState {
        let collector = NativeDLNAStateParser()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !collector.invalid, collector.stack.isEmpty,
              collector.occurrences == 1, let state = collector.state else {
            throw NativeDLNAError.invalidResponse
        }
        return state
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let ns = namespaceURI ?? ""
        if collecting { invalid = true } // No nested elements inside the state value.
        if elementName == "CurrentTransportState" {
            let correctPath = stack.count == 3 &&
                stack[0].name == "Envelope" && stack[0].namespace == envelope &&
                stack[1].name == "Body" && stack[1].namespace == envelope &&
                stack[2].name == "GetTransportInfoResponse" &&
                stack[2].namespace == NativeDLNA.service
            guard correctPath, ns.isEmpty || ns == NativeDLNA.service,
                  occurrences == 0 else {
                invalid = true
                stack.append((elementName, ns))
                return
            }
            occurrences += 1
            raw = ""
            collecting = true
        }
        stack.append((elementName, ns))
    }

    private func appendStateText(_ text: String) {
        guard collecting else { return }
        raw += text
        if raw.utf8.count > 64 { invalid = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendStateText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard collecting else { return }
        guard let text = String(data: CDATABlock, encoding: .utf8) else {
            invalid = true
            return
        }
        appendStateText(text)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if collecting && stack.count == 4 && elementName == "CurrentTransportState" {
            state = NativeDLNATransportState(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            if state == nil { invalid = true }
            collecting = false
        }
        guard let last = stack.popLast(), last.name == elementName,
              last.namespace == (namespaceURI ?? "") else {
            invalid = true
            return
        }
    }
}
