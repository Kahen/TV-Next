import { describe, expect, it } from "vitest";
import type { Channel } from "./api";
import {
  addRecent, clearLibrary, emptyLibrary, loadLibrary, normalizeLibrary, saveLibrary,
  replacePlaylistChannels, setPosition, STORAGE_KEY, toggleFavorite, validMediaUrl
} from "./library";
import type { StorageLike } from "./library";

const a: Channel = { name: "Example", url: "https://example.org/film.mp4", group: "Test" };
const b: Channel = { name: "Live", url: "https://example.org/live.m3u8", group: "TV" };

function memoryStorage(): StorageLike {
  const data = new Map<string, string>();
  return {
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => { data.set(key, value); },
    removeItem: (key) => { data.delete(key); }
  };
}

describe("local media library", () => {
  it("checks protocols and blocks credentials", () => {
    expect(validMediaUrl(a.url)).toBe(true);
    for (const url of ["javascript:alert(1)", "file:///private", "https://name:secret@host/path", "example.org", " https://example.org", "https://example.org/\n#EXTINF:-1", "https://example.org/\r\nunsafe"]) {
      expect(validMediaUrl(url)).toBe(false);
    }
  });

  it("persists only valid data and survives reload", () => {
    const storage = memoryStorage();
    const state = addRecent({ ...emptyLibrary(), channels: [a, b] }, a, 123);
    expect(saveLibrary(state, storage)).toBe(true);
    expect(loadLibrary(storage)).toEqual(state);
    expect(clearLibrary(storage)).toBe(true);
    expect(loadLibrary(storage)).toEqual(emptyLibrary());
  });

  it("recovers from corrupted and unsupported schema", () => {
    const storage = memoryStorage();
    storage.setItem(STORAGE_KEY, "not json");
    expect(loadLibrary(storage)).toEqual(emptyLibrary());
    storage.setItem(STORAGE_KEY, '{"version":2}');
    expect(loadLibrary(storage)).toEqual(emptyLibrary());
    const invalid: unknown = {
      version: 1, channels: [a, a, { name: "bad", group: "X", url: "javascript:alert(1)" }],
      favorites: [a.url, a.url, "file:///etc/passwd"],
      recent: [{ channel: b, openedAt: 50 }],
      positions: { [a.url]: 120, [b.url]: Number.NaN }
    };
    const state = normalizeLibrary(invalid);
    expect(state.channels).toEqual([a]);
    expect(state.favorites).toEqual([a.url]);
    expect(state.recent[0].channel).toEqual(b);
    expect(state.positions[a.url]).toBe(120);
    expect(state.positions[b.url]).toBeUndefined();
  });

  it("rejects oversized UTF-8 snapshots on load", () => {
    const storage = memoryStorage();
    const snapshot = JSON.stringify({ version: 1, channels: [a], padding: "😀".repeat(510_000) });
    expect(snapshot.length).toBeLessThan(2_000_000);
    expect(new TextEncoder().encode(snapshot).byteLength).toBeGreaterThan(2_000_000);
    storage.setItem(STORAGE_KEY, snapshot);
    expect(loadLibrary(storage)).toEqual(emptyLibrary());
  });

  it("preserves the previous snapshot when a Unicode-heavy save exceeds the byte budget", () => {
    const storage = memoryStorage();
    expect(saveLibrary({ ...emptyLibrary(), channels: [a] }, storage)).toBe(true);
    const channels: Channel[] = Array.from({ length: 1500 }, (_, index) => ({
      name: "😀".repeat(100), group: "😀".repeat(50),
      url: "https://example.org/" + index + "/" + "x".repeat(730)
    }));
    const serialized = JSON.stringify(normalizeLibrary({ ...emptyLibrary(), channels }));
    expect(serialized.length).toBeLessThan(2_000_000);
    expect(new TextEncoder().encode(serialized).byteLength).toBeGreaterThan(2_000_000);
    expect(saveLibrary({ ...emptyLibrary(), channels }, storage)).toBe(false);
    expect(loadLibrary(storage).channels).toEqual([a]);
  });

  it("handles storage permission/quota failure", () => {
    const failing: StorageLike = {
      getItem: () => { throw new Error("blocked"); },
      setItem: () => { throw new Error("quota"); },
      removeItem: () => { throw new Error("blocked"); }
    };
    expect(loadLibrary(failing)).toEqual(emptyLibrary());
    expect(saveLibrary(emptyLibrary(), failing)).toBe(false);
    expect(clearLibrary(failing)).toBe(false);
  });

  it("deduplicates recent streams and toggles favorites", () => {
    const first = addRecent(emptyLibrary(), a, 1);
    const newer = addRecent(addRecent(first, b, 2), a, 3);
    expect(newer.recent.map((entry) => entry.channel.url)).toEqual([a.url, b.url]);
    expect(newer.recent[0].openedAt).toBe(3);
    expect(toggleFavorite(toggleFavorite(first, a.url), a.url).favorites).toEqual([]);
  });

  it("resumes VOD only and clears near completion", () => {
    const start = emptyLibrary();
    const resumed = setPosition(start, a.url, 99.8, 200);
    expect(resumed.positions[a.url]).toBe(99);
    expect(setPosition(resumed, a.url, 190, 200).positions[a.url]).toBeUndefined();
    expect(setPosition(start, b.url, 30, Infinity)).toEqual(start);
  });
});

// Sensitive media request headers stay in active playback memory, never local snapshots.
it("does not persist Cookie or Authorization headers and marks required reload", () => {
  const state=emptyLibrary();state.channels=[{name:"Own",url:"https://example.org/a",group:"Cloud",headers:{Cookie:"own-secret","User-Agent":"TV-Next"}}];
  const normalized=normalizeLibrary(state);
  expect(normalized.channels[0].headers).toEqual({"User-Agent":"TV-Next"});
  expect(normalized.channels[0].headersRequired).toBe(true);
  expect(JSON.stringify(normalized)).not.toContain("own-secret");
});


describe("playlist import integrity", () => {
  it("keeps existing channels, favorites, recents and positions when the parsed playlist is empty", () => {
    const before = { ...emptyLibrary(), channels: [a], favorites: [a.url],
      recent: [{ channel: a, openedAt: 123 }], positions: { [a.url]: 85 } };
    const result = replacePlaylistChannels(before, { channels: [], total: 0 });
    expect(result.applied).toBe(false);
    expect(result.state).toBe(before);
    expect(result.warning).toContain("保留");
    const storage = memoryStorage();
    expect(saveLibrary(result.state, storage)).toBe(true);
    expect(loadLibrary(storage)).toEqual(before);
  });

  it("does not erase a valid library when all parsed URLs are invalid", () => {
    const before = { ...emptyLibrary(), channels: [a] };
    const result = replacePlaylistChannels(before, {
      channels: [{ name: "Unsafe", group: "Test", url: "javascript:alert(1)" }],
      total: 1
    });
    expect(result.applied).toBe(false);
    expect(result.state).toBe(before);
  });

  it("replaces channels while retaining user metadata and caps oversized lists", () => {
    const before = { ...emptyLibrary(), channels: [a], favorites: [a.url],
      recent: [{ channel: a, openedAt: 123 }], positions: { [a.url]: 85 } };
    const incoming: Channel[] = Array.from({ length: 1501 }, (_, index) => ({
      name: "New " + index, group: "Imported", url: "https://example.org/new/" + index
    }));
    const result = replacePlaylistChannels(before, { channels: incoming, total: 1501 });
    expect(result.applied).toBe(true);
    expect(result.state.channels).toHaveLength(1500);
    expect(result.state.favorites).toEqual([a.url]);
    expect(result.state.recent).toEqual(before.recent);
    expect(result.state.positions).toEqual(before.positions);
    expect(result.warning).toContain("1500");
  });

  it("retains in-memory stream headers for playback while storage sanitizes secrets", () => {
    const before = emptyLibrary();
    const channel: Channel = { name: "Own", group: "Test", url: "https://example.org/own",
      headers: { Cookie: "private-token", "User-Agent": "TV-Next" } };
    const result = replacePlaylistChannels(before, { channels: [channel], total: 1 });
    expect(result.state.channels[0].headers?.Cookie).toBe("private-token");
    const storage = memoryStorage();
    expect(saveLibrary(result.state, storage)).toBe(true);
    expect(loadLibrary(storage).channels[0].headers).toEqual({ "User-Agent": "TV-Next" });
    expect(loadLibrary(storage).channels[0].headersRequired).toBe(true);
  });
});
