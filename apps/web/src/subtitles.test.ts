import { describe, expect, it } from "vitest";
import { toWebVtt } from "./subtitles";

describe("text subtitle conversion", () => {
  it("converts SRT with BOM and CRLF", () => {
    const source = "\uFEFF1\r\n00:00:01,250 --> 00:00:03,750\r\nHello\r\nWorld\r\n\r\n2\r\n00:01:01,000 --> 00:01:05,250\r\nSecond";
    const result = toWebVtt(source, "caption.srt");
    expect(result).toContain("00:00:01.250 --> 00:00:03.750");
    expect(result).toContain("Hello\nWorld");
    expect(result).toContain("00:01:01.000 --> 00:01:05.250");
  });
  it("passes through valid VTT", () => {
    expect(toWebVtt("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHi", "en.vtt")).toMatch(/^WEBVTT/);
  });
  it("rejects unsupported or malformed captions", () => {
    expect(() => toWebVtt("broken", "broken.srt")).toThrow("时间轴");
    expect(() => toWebVtt("TEXT", "broken.ass")).toThrow("仅支持");
    expect(() => toWebVtt("", "empty.srt")).toThrow("字幕");
    expect(() => toWebVtt("A".repeat(1_048_577), "big.srt")).toThrow("1 MiB");
  });
});
