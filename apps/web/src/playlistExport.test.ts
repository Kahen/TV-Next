import { expect, it } from "vitest";
import { exportM3u } from "./playlistExport";

it("exports M3U while sanitizing control characters", () => {
  const text = exportM3u([
    { name: "A\nB", group: 'TV"News', tvgId: "ch1", url: "https://example.org/stream.mp4" },
    { name: "Bad", group: "x", url: "javascript:alert(1)" }
  ]);
  expect(text).toContain("#EXTM3U\n");
  expect(text).toContain('group-title="TV News" tvg-id="ch1",A B');
  expect(text).toContain("https://example.org/stream.mp4");
  expect(text).not.toContain("javascript:");
});
