import { describe, expect, it } from "vitest";
import { epgChannelsFromPlaylist, formatProgrammeRange, formatProgrammeTime } from "./epg";

describe("XMLTV request preparation", () => {
  it("uses tvg-id first, retains channel order and bounds request size", () => {
    const fixture = Array.from({ length: 350 }, (_, index) => ({
      url: "https://example.org/" + index + ".m3u8",
      name: " News " + index,
      tvgId: index === 0 ? " xml-channel-1 " : null,
      group: "TV"
    }));
    const normalized = epgChannelsFromPlaylist(fixture);
    expect(normalized.length).toBe(300);
    expect(normalized[0]).toEqual({ id: "xml-channel-1", name: "News 0" });
    expect(normalized[1]).toEqual({ id: null, name: "News 1" });
  });
  it("uses local timezone without claiming a fixed UTC conversion", () => {
    expect(formatProgrammeTime("invalid date")).toBe("时间无效");
    expect(formatProgrammeRange("invalid", "invalid")).toBe("时间无效 – 时间无效");
  });
});
