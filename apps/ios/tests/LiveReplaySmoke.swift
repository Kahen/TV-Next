import Foundation
@main struct LiveReplaySmoke {
    static func main() throws {
        let bytes=try Data(contentsOf:URL(fileURLWithPath:"../../fixtures/fongmi-live-replay-golden.json"))
        let root=try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
        let shift=try JSONDecoder().decode(NativeTimeshift.self,from:JSONSerialization.data(withJSONObject:root["timeshift"]!))
        let now=(root["now"] as! NSNumber).int64Value
        let time=(root["time"] as! NSNumber).int64Value
        precondition(shift.range(now:now)==time...now)
        precondition(NativeTimeshift(url:shift.url,start:now,window:1).range(now:now)==nil)
        precondition(NativeTimeshift(url:shift.url,start:1,window:-1).range(now:now)==nil)
        precondition(NativeTimeshift(url:"https://example.org/no-token",start:1,window:10).range(now:now)==nil)
        var channel=TVChannel(name:"News",url:root["liveUrl"] as! String,group:"Live",logo:nil,tvgId:nil,timeshift:shift)
        channel.replay=NativeReplaySession(path:"/api/v1/home/media/"+String(repeating:"a",count:43)+"/0",expiresAt:now+1000,hls:true,time:time)
        let encoded=try JSONEncoder().encode(channel)
        precondition(!String(data:encoded,encoding:.utf8)!.contains("/api/v1/home/media/"))
        let restored=try JSONDecoder().decode(TVChannel.self,from:encoded)
        precondition(restored.replay == nil)
        let parsed=try M3UParser.parse("#EXTM3U catchup=\"append\" catchup-source=\"?begin={utc:0}\"\n#EXTINF:-1,One\nhttps://example.org/a\n#EXTINF:-1 catchup=\"default\" catchup-source=\"https://example.org/replay?b={utc:0}\",Two\nhttps://example.org/b\n#EXTINF:-1,Three\nhttps://example.org/c")
        precondition(parsed.map { $0.catchup?.type } == ["append","default","append"])
        print("Native FongMi timeshift window, M3U catchup inheritance and ephemeral relay contract passed")
    }
}
