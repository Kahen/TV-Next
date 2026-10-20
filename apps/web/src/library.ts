import type { Channel } from "./api";

export interface RecentChannel {
  channel: Channel;
  openedAt: number;
}

export interface LibraryState {
  version: 1;
  channels: Channel[];
  favorites: string[];
  recent: RecentChannel[];
  positions: Record<string, number>;
}

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export const STORAGE_KEY = "tv-next-library-v1";
const MAX_CHANNELS = 1500;
const MAX_FAVORITES = 300;
const MAX_RECENT = 100;
const MAX_POSITIONS = 250;
const MAX_STORED_BYTES = 2_000_000;

export function emptyLibrary(): LibraryState {
  return { version: 1, channels: [], favorites: [], recent: [], positions: {} };
}

export function validMediaUrl(value: string): boolean {
  if (typeof value !== "string" || value.length > 2048 || value !== value.trim()) return false;
  try {
    const parsed = new URL(value);
    return (parsed.protocol === "http:" || parsed.protocol === "https:")
      && Boolean(parsed.hostname) && !parsed.username && !parsed.password;
  } catch {
    return false;
  }
}

function asChannel(input: unknown): Channel | null {
  if (!input || typeof input !== "object") return null;
  const value = input as Partial<Channel>;
  if (!validMediaUrl(value.url ?? "") || typeof value.name !== "string" ||
      typeof value.group !== "string") return null;
  return {
    url: value.url!,
    name: value.name.slice(0, 200),
    group: value.group.slice(0, 100),
    logo: typeof value.logo === "string" && validMediaUrl(value.logo) ? value.logo : null,
    tvgId: typeof value.tvgId === "string" ? value.tvgId.slice(0, 150) : null
  };
}

function normalizedChannels(value: unknown, limit: number): Channel[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const result: Channel[] = [];
  for (const raw of value.slice(0, 5_000)) {
    const channel = asChannel(raw);
    if (!channel || seen.has(channel.url)) continue;
    seen.add(channel.url);
    result.push(channel);
    if (result.length >= limit) break;
  }
  return result;
}

function normalizedUrlList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((item): item is string =>
    typeof item === "string" && validMediaUrl(item)))].slice(0, MAX_FAVORITES);
}

export function normalizeLibrary(value: unknown): LibraryState {
  if (!value || typeof value !== "object" || (value as { version?: unknown }).version !== 1) {
    return emptyLibrary();
  }
  const raw = value as Partial<LibraryState>;
  const recent: RecentChannel[] = [];
  const recentUrls = new Set<string>();
  if (Array.isArray(raw.recent)) {
    for (const item of raw.recent.slice(0, MAX_RECENT * 3)) {
      if (!item || typeof item !== "object") continue;
      const entry = item as Partial<RecentChannel>;
      const channel = asChannel(entry.channel);
      if (!channel || recentUrls.has(channel.url)) continue;
      if (typeof entry.openedAt !== "number" || !Number.isFinite(entry.openedAt)) continue;
      recentUrls.add(channel.url);
      recent.push({ channel, openedAt: entry.openedAt });
      if (recent.length === MAX_RECENT) break;
    }
  }
  const positions: Record<string, number> = Object.create(null) as Record<string, number>;
  if (raw.positions && typeof raw.positions === "object" && !Array.isArray(raw.positions)) {
    for (const [url, position] of Object.entries(raw.positions).slice(0, MAX_POSITIONS * 3)) {
      if (validMediaUrl(url) && typeof position === "number" &&
          Number.isFinite(position) && position >= 0 && position < 604800) {
        positions[url] = position;
        if (Object.keys(positions).length === MAX_POSITIONS) break;
      }
    }
  }
  return {
    version: 1,
    channels: normalizedChannels(raw.channels, MAX_CHANNELS),
    favorites: normalizedUrlList(raw.favorites),
    recent,
    positions
  };
}

function browserStorage(): StorageLike | null {
  try {
    return typeof window !== "undefined" ? window.localStorage : null;
  } catch {
    return null;
  }
}

export function loadLibrary(storage: StorageLike | null = browserStorage()): LibraryState {
  if (!storage) return emptyLibrary();
  try {
    const text = storage.getItem(STORAGE_KEY);
    if (!text || text.length > MAX_STORED_BYTES) return emptyLibrary();
    return normalizeLibrary(JSON.parse(text) as unknown);
  } catch {
    return emptyLibrary();
  }
}

export function saveLibrary(value: LibraryState, storage: StorageLike | null = browserStorage()): boolean {
  if (!storage) return false;
  try {
    const text = JSON.stringify(normalizeLibrary(value));
    if (text.length > MAX_STORED_BYTES) return false;
    storage.setItem(STORAGE_KEY, text);
    return true;
  } catch {
    return false;
  }
}

export function clearLibrary(storage: StorageLike | null = browserStorage()): boolean {
  if (!storage) return false;
  try {
    storage.removeItem(STORAGE_KEY);
    return true;
  } catch {
    return false;
  }
}

export function addRecent(state: LibraryState, channel: Channel, now = Date.now()): LibraryState {
  const normalized = asChannel(channel);
  if (!normalized) return state;
  return {
    ...state,
    recent: [
      { channel: normalized, openedAt: now },
      ...state.recent.filter((entry) => entry.channel.url !== normalized.url)
    ].slice(0, MAX_RECENT)
  };
}

export function toggleFavorite(state: LibraryState, url: string): LibraryState {
  if (!validMediaUrl(url)) return state;
  const exists = state.favorites.includes(url);
  return {
    ...state,
    favorites: exists ? state.favorites.filter((item) => item !== url) :
      [url, ...state.favorites].slice(0, MAX_FAVORITES)
  };
}

export function setPosition(state: LibraryState, url: string, current: number, duration: number): LibraryState {
  if (!validMediaUrl(url) || !Number.isFinite(current) || !Number.isFinite(duration) ||
      current < 0 || duration < 60) return state;
  const positions = { ...state.positions };
  if (current < 5 || duration - current < 15) {
    delete positions[url];
  } else {
    positions[url] = Math.floor(current);
  }
  return { ...state, positions: Object.fromEntries(Object.entries(positions).slice(-MAX_POSITIONS)) };
}
