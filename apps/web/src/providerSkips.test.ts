import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { normalizeProviderSkips, providerSkipTarget } from "./providerSkips";
import { addRecent, emptyLibrary, normalizeLibrary } from "./library";

const fixture = JSON.parse(readFileSync(
  new URL("../../../fixtures/fongmi-provider-skips-golden.json", import.meta.url), "utf8"
)) as {
  expected: unknown;
  positions: { seconds: number; duration: number; type: string | null; target: number | null }[];
};

describe("normalized provider segments", () => {
  it("matches the JVM/Swift shared millisecond and EOF targets", () => {
    const segments = normalizeProviderSkips(fixture.expected);
    expect(segments).toEqual(fixture.expected);
    for (const position of fixture.positions) {
      const active = segments.find(segment => providerSkipTarget(segment, position.seconds, position.duration) !== null);
      expect(active?.type ?? null).toBe(position.type);
      expect(active ? providerSkipTarget(active, position.seconds, position.duration) : null).toBe(position.target);
    }
  });
  it("rejects malformed data and preserves first occurrence under both bounds", () => {
    const valid = {type: "opening", startMs: 0, endMs: 1000};
    expect(normalizeProviderSkips([null, {}, valid, valid, {...valid, endMs: "1000"}, {...valid, startMs: 0.5}])).toEqual([valid]);
    expect(normalizeProviderSkips(Array(128).fill(null).concat(valid))).toEqual([]);
    expect(normalizeProviderSkips(Array(127).fill(null).concat(valid))).toEqual([valid]);
    expect(normalizeProviderSkips(Array.from({length: 50}, (_, i) => ({type: "middle", startMs: i, endMs: i + 1})))).toHaveLength(32);
    const segment = normalizeProviderSkips([valid])[0];
    for (const duration of [NaN, Infinity, 0, -1, 604800, 0.5]) expect(providerSkipTarget(segment, 0, duration)).toBeNull();
  });
  it("does not persist or restore source hints through library/history", () => {
    const channel = {name: "Owned", group: "Test", url: "https://example.org/movie.mp4", skipSegments: normalizeProviderSkips(fixture.expected)};
    const state = addRecent(emptyLibrary(), channel);
    expect(state.recent[0].channel.skipSegments).toBeUndefined();
    expect(normalizeLibrary({...state, channels: [channel]}).channels[0].skipSegments).toBeUndefined();
  });
});
