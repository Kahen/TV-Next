import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct DLNADescriptionSmoke {
    static func main() throws {
        let location = try NativeDLNADescription.location("http://127.0.0.1:8768/device.xml")
        func xml(_ services: String, namespace: String = NativeDLNADescription.deviceNamespace) -> Data {
            Data("<root xmlns=\"\(namespace)\"><device><serviceList>\(services)</serviceList></device></root>".utf8)
        }
        func service(_ type: String = NativeDLNA.service, _ control: String = "/upnp/control/AVTransport1") -> String {
            "<service><serviceType>\(type)</serviceType><controlURL>\(control)</controlURL></service>"
        }
        let parsed = try NativeDLNADescription.parse(xml(service()), location: location)
        let unnamed = try NativeDLNADescription.parseDetails(xml(service()), location: location)
        precondition(unnamed.friendlyName == nil && unnamed.modelName == nil)
        let named = Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device><friendlyName>客厅电视 TV-Next</friendlyName><modelName>TV-Next Model 1</modelName><serviceList>\(service())</serviceList></device></root>".utf8)
        let details = try NativeDLNADescription.parseDetails(named, location: location)
        precondition(details.controlURL == parsed && details.friendlyName == "客厅电视 TV-Next" && details.modelName == "TV-Next Model 1")
        precondition(parsed.absoluteString == "http://127.0.0.1:8768/upnp/control/AVTransport1")

        // Discovery promotion must bind the SSDP USN to the root-device UDN.
        // The manually typed description URL remains compatible without UDN.
        let discoveredLocation = URL(string: "http://192.168.1.20:1400/device.xml")!
        let target = NativeSSDPResponse.mediaRenderer
        let candidate = NativeSSDPResponse.Candidate(
            location: discoveredLocation, serviceType: target,
            uniqueServiceName: "uuid:owned-device::" + target)
        func identityXML(_ fields: String) -> Data {
            Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device>\(fields)<serviceList>\(service())</serviceList></device></root>".utf8)
        }
        let identity = identityXML("<UDN>uuid:Owned-Device</UDN>")
        let approved = try NativeDLNADescription.verifyDiscovered(identity, candidate: candidate)
        precondition(approved.deviceUDN == "uuid:Owned-Device")
        precondition(approved.controlURL.absoluteString == "http://192.168.1.20:1400/upnp/control/AVTransport1")
        precondition(NativeSSDPResponse.matchesDescriptionUDN(candidate, udn: approved.deviceUDN))
        for body in [identityXML(""), identityXML("<UDN>uuid:another-device</UDN>")] {
            do {
                _ = try NativeDLNADescription.verifyDiscovered(body, candidate: candidate)
                fatalError("Accepted missing/mismatched SSDP device identity")
            } catch NativeDLNAError.invalidDescription {}
        }
        let wrongTarget = NativeSSDPResponse.Candidate(
            location: discoveredLocation, serviceType: "ssdp:all",
            uniqueServiceName: "uuid:owned-device::ssdp:all")
        precondition(!NativeSSDPResponse.matchesDescriptionUDN(wrongTarget, udn: "uuid:owned-device"))
        let malformedIdentities = [
            "<UDN/>", "<UDN>uuid:</UDN>", "<UDN>uuid:bad identity</UDN>",
            "<UDN>uuid:bad\\nidentity</UDN>", "<UDN>uuid:bad\\u{202E}id</UDN>",
            "<UDN>uuid:one</UDN><UDN>uuid:two</UDN>",
            "<UDN><child>uuid:owned-device</child></UDN>",
            "<x:UDN xmlns:x=\"urn:foreign\">uuid:owned-device</x:UDN>",
            "<UDN>uuid:\(String(repeating: "A", count: 124))</UDN>"
        ]
        for field in malformedIdentities {
            do {
                _ = try NativeDLNADescription.parseDetails(identityXML(field), location: discoveredLocation)
                fatalError("Accepted malformed root UDN")
            } catch NativeDLNAError.invalidDescription {}
        }

        let ignored = service("urn:schemas-upnp-org:service:RenderingControl:1", "/other")
        let withOtherService = try NativeDLNADescription.parse(xml(ignored + service()), location: location)
        precondition(withOtherService == parsed)
        let extended = Data("<root xmlns=\"urn:schemas-upnp-org:device-1-0\"><device><vendor:feature xmlns:vendor=\"urn:vendor\">ignored</vendor:feature><serviceList>\(service())</serviceList></device></root>".utf8)
        let withExtension = try NativeDLNADescription.parse(extended, location: location)
        precondition(withExtension == parsed)
        let relative = try NativeDLNADescription.parse(xml(service(NativeDLNA.service, "upnp/control/AVTransport1")), location: location)
        precondition(relative == parsed)
        let sameOrigin = try NativeDLNADescription.parse(xml(service(NativeDLNA.service, "http://127.0.0.1:8768/upnp/control/AVTransport1")), location: location)
        precondition(sameOrigin == parsed)
        let cdata = try NativeDLNADescription.parse(xml(service(NativeDLNA.service, "<![CDATA[/upnp/control/AVTransport1]]>")), location: location)
        precondition(cdata == parsed)
        let duplicateName = Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device><friendlyName>One</friendlyName><friendlyName>Two</friendlyName><serviceList>\(service())</serviceList></device></root>".utf8)
        let nestedName = Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device><friendlyName><fake>Forged</fake></friendlyName><serviceList>\(service())</serviceList></device></root>".utf8)
        let unsafeName = Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device><friendlyName>Bad\u{202E}Name</friendlyName><serviceList>\(service())</serviceList></device></root>".utf8)
        let longName = Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device><friendlyName>\(String(repeating: "A", count: 161))</friendlyName><serviceList>\(service())</serviceList></device></root>".utf8)
        let modelOnly = Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device><modelName>独立型号</modelName><serviceList>\(service())</serviceList></device></root>".utf8)
        let modelOnlyDetails = try NativeDLNADescription.parseDetails(modelOnly, location: location)
        precondition(modelOnlyDetails.modelName == "独立型号")
        let boundaryModel = Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device><modelName>\(String(repeating: "é", count: 80))</modelName><serviceList>\(service())</serviceList></device></root>".utf8)
        let boundaryDetails = try NativeDLNADescription.parseDetails(boundaryModel, location: location)
        precondition(boundaryDetails.modelName?.utf8.count == 160)
        func withModel(_ model: String) -> Data {
            Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device>\(model)<serviceList>\(service())</serviceList></device></root>".utf8)
        }
        let invalidModels = [
            "<modelName>One</modelName><modelName>Two</modelName>",
            "<modelName>Model<fake/>Name</modelName>",
            "<x:modelName xmlns:x=\"urn:foreign\">Forged</x:modelName>",
            "<modelName>Bad\u{202E}Name</modelName>",
            "<modelName>Bad\nName</modelName>",
            "<modelName>\(String(repeating: "é", count: 81))</modelName>"
        ].map(withModel)
        let multipleDevices = Data("<root xmlns=\"\(NativeDLNADescription.deviceNamespace)\"><device><friendlyName>First</friendlyName></device><device><modelName>Second</modelName><serviceList>\(service())</serviceList></device></root>".utf8)
        let invalid: [Data] = [duplicateName, nestedName, unsafeName, longName, multipleDevices] + invalidModels + [
            xml(""), xml(service() + service()),
            xml(service(NativeDLNA.service, "http://8.8.8.8:8768/upnp/control")),
            xml(service(NativeDLNA.service, "http://127.0.0.1:9999/upnp/control")),
            xml(service(NativeDLNA.service, "//127.0.0.1:8768/upnp/control")),
            xml(service(NativeDLNA.service, "/../admin")),
            xml(service(NativeDLNA.service, "/upnp/%2e%2e/admin")),
            xml(service(NativeDLNA.service, "/upnp/control?token=x")),
            xml(service(NativeDLNA.service, "/upnp/control#fragment")),
            xml(service(NativeDLNA.service, "file:///private/secret")),
            xml(service(NativeDLNA.service, "<fake>/upnp/control</fake>")),
            xml(service().replacingOccurrences(of: "</service>", with: "<controlURL>/another</controlURL></service>")),
            xml("<outer>" + service() + "</outer>"),
            xml(service(), namespace: "urn:untrusted"),
            Data("<!DOCTYPE root [<!ENTITY x SYSTEM \"file:///etc/passwd\">]>".utf8) + xml(service()),
            Data(repeating: 65, count: NativeDLNA.maxResponseBytes + 1)
        ]
        for (index, body) in invalid.enumerated() {
            do {
                _ = try NativeDLNADescription.parse(body, location: location)
                fatalError("Accepted invalid device description #\(index)")
            } catch NativeDLNAError.invalidDescription { }
        }
        for unsafe in ["https://127.0.0.1:8768/device.xml", "http://8.8.8.8:8768/device.xml",
                       "http://example.com:8768/device.xml", "http://127.0.0.1/device.xml",
                       "http://user:pw@127.0.0.1:8768/device.xml", "http://127.0.0.1:8768/device.xml?x=1"] {
            do { _ = try NativeDLNADescription.location(unsafe); fatalError("Accepted unsafe location") }
            catch NativeDLNAError.invalidRenderer { }
        }
        print("Bounded LAN UPnP device description parser positive/negative smoke passed")
    }
}
