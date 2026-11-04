import Foundation
@main struct DanmakuSmoke {
    static func main() throws {
        let comments = try DanmakuParser.parse("<i><d p=\"1.5,1,25,16711680\">A &amp; B</d><d p=\"2,5,25,16777215\">顶部</d><d p=\"3,7,25,0\">script</d></i>")
        precondition(comments.count == 2 && comments[0].time == 1.5 && comments[0].color == 0xff0000 && comments[0].text == "A & B")
        // Nested <d> must not replace an already-open outer comment or emit a duplicate.
        let nested = try DanmakuParser.parse("<i><d p=\"1,1,25,16777215\">outer<d p=\"2,1,25,16711680\">inner</d>tail</d><d p=\"3,1,25,16777215\">next</d></i>")
        precondition(nested.count == 2 && nested[0].time == 1 && nested[0].text == "outerinnertail")
        precondition(nested[1].time == 3 && nested[1].text == "next")
        let json = try DanmakuParser.parse("{\"comments\":[{\"p\":\"2,1,16777215,uid\",\"m\":\"hello\"}]}")
        precondition(json.count == 1 && json[0].text == "hello")
        // Malformed JSON must expose the same bounded parser error as malformed XML,
        // not Foundation's platform-dependent JSONSerialization NSError.
        for malformed in ["{", "{\\\"comments\\\":[", "[not-json]"] {
            do {
                _ = try DanmakuParser.parse(malformed)
                fatalError("Malformed JSON accepted")
            } catch DanmakuError.invalid {
                // Expected stable public error taxonomy.
            } catch {
                fatalError("Unexpected malformed JSON error: \\(error)")
            }
        }
        do { _ = try DanmakuParser.parse("<!DOCTYPE i [<!ENTITY a SYSTEM 'file:///etc/passwd'>]><i/>"); fatalError("DTD accepted") } catch {}
        print("Native danmaku compatibility smoke passed")
    }
}
