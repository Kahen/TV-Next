// @vitest-environment jsdom
import { describe, it, expect } from "vitest";
import { parseDanmaku, scheduleDanmaku } from "./danmaku";
describe("upstream danmaku compatibility", () => {
  it("uses seconds, mode, size, integer RGB and XML entity decoding", () => {
    expect(parseDanmaku('<i><d p="1.5,1,25,16711680,0">A &amp; B</d><d p="2,5,25,16777215">顶部</d></i>'))
      .toEqual([{time:1.5,mode:1,size:25,color:"#ff0000",text:"A & B"},{time:2,mode:5,size:25,color:"#ffffff",text:"顶部"}]);
  });
  it("accepts dandanplay and rejects script modes, bad colors, DTDs and oversized input", () => {
    expect(parseDanmaku('{"comments":[{"p":"2,1,16777215,uid","m":"hello"}]}')).toHaveLength(1);
    expect(parseDanmaku('<i><d p="1,7,25,0">code</d><d p="NaN,1,25,0">bad</d></i>')).toEqual([]);
    expect(() => parseDanmaku('<!DOCTYPE i [<!ENTITY a SYSTEM "file:///etc/passwd">]><i/>')).toThrow();
    expect(() => parseDanmaku('😀'.repeat(524289))).toThrow();
  });
  it("drops colliding comments, permits free lanes and deterministic seek reconstruction", () => {
    const c = parseDanmaku('<i><d p="0,1,25,0">one</d><d p="0,1,25,0">two</d><d p="9,1,25,0">three</d></i>');
    const scheduled = scheduleDanmaku(c, 800, 1, 8, () => 100);
    expect(scheduled.map(c => c.text)).toEqual(["one", "three"]);
    expect(scheduleDanmaku(c,800,2,8,()=>100)).toHaveLength(3);
    expect(scheduleDanmaku(c,800,1,8,()=>100)).toEqual(scheduled);
  });
});
