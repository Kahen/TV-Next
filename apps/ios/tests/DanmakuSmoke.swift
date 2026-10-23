import Foundation
@main struct DanmakuSmoke {
    static func main() throws {
        let comments = try DanmakuParser.parse("<i><d p=\"1.5,1,25,16711680\">A &amp; B</d><d p=\"2,5,25,16777215\">顶部</d><d p=\"3,7,25,0\">script</d></i>")
        precondition(comments.count == 2 && comments[0].time == 1.5 && comments[0].color == 0xff0000 && comments[0].text == "A & B")
        let json = try DanmakuParser.parse("{\"comments\":[{\"p\":\"2,1,16777215,uid\",\"m\":\"hello\"}]}")
        precondition(json.count == 1 && json[0].text == "hello")
        do { _ = try DanmakuParser.parse("<!DOCTYPE i [<!ENTITY a SYSTEM 'file:///etc/passwd'>]><i/>"); fatalError("DTD accepted") } catch {}
        print("Native danmaku compatibility smoke passed")
    }
}
