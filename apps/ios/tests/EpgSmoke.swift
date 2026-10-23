import Foundation
@main struct EpgSmoke {
    static func main() throws {
        let data=try Data(contentsOf:URL(fileURLWithPath:"../../fixtures/p2-epg-guide.json"))
        let guide=try JSONDecoder().decode(NativeEpgGuide.self,from:data)
        precondition(guide.matchedChannels==1)
        precondition(guide.channels[0].current?.title=="今日新闻")
        precondition(guide.channels[0].current?.start=="2026-10-23T04:00:00Z")
        precondition(guide.channels[1].matchType=="none")
        precondition(guide.channels[1].current==nil)
        let request=NativeEpgRequest(channels:[NativeEpgChannelRequest(id:"news",name:"News")])
        let object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(request)) as! [String:Any]
        precondition(object["xml"]==nil)
        precondition((object["channels"] as! [[String:Any]])[0]["id"] as? String=="news")
        print("Native XMLTV contract and subscription models passed")
    }
}
