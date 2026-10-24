import Foundation

@main struct MediaRelaySmoke {
    static func main() throws {
        let ticket=String(repeating:"a",count:43)
        let path="/api/v1/home/media/"+ticket+"/0"
        let result=try MediaRelayAddress.resolve(path,server:URL(string:"https://home.example:8443")!)
        precondition(result.ticket==ticket)
        precondition(result.url.absoluteString=="https://home.example:8443"+path)
        for bad in ["https://other.example/a","//other.example/a",path+"?token=secret",path+"/../0"] {
            do { _=try MediaRelayAddress.resolve(bad,server:URL(string:"https://home.example")!);fatalError("Unsafe relay address accepted") } catch { }
        }
        do { _=try MediaRelayAddress.resolve(path,server:URL(string:"https://user:password@home.example")!);fatalError("Credential-bearing server accepted") } catch { }
        let decoded=try JSONDecoder().decode(NativeRelayResponse.self,from:JSONSerialization.data(withJSONObject:["path":path,"expiresAt":123]))
        precondition(decoded.path==path)
        print("Native media relay capability contract passed")
    }
}
