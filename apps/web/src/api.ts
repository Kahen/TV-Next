export interface Channel {
  name: string;
  url: string;
  group: string;
  logo?: string | null;
  tvgId?: string | null;
  headers?: Record<string, string>;
  headersRequired?: boolean;
  subtitles?: PlaybackResource[];
  danmaku?: PlaybackResource[];
}
export interface PlaylistResult {
  channels: Channel[];
  total: number;
}
export interface ConfigPreview {
  spiderDeclared: boolean;
  sites: { key: string; name: string; type: number | null }[];
  liveGroupCount: number;
}
export interface CatalogPreview {
  sites: {
    key: string;
    name: string;
    type: number | null;
    searchable: boolean;
    hidden: boolean;
    categories: string[];
    mode: "preview-only";
  }[];
  liveSources: {
    name: string;
    groups: {
      name: string;
      channels: { name: string; directUrl: string | null; sourceCount: number }[];
    }[];
  }[];
  directPlayableChannelCount: number;
  warnings: string[];
}
const base = import.meta.env.VITE_API_BASE_URL || "";
export async function postText<T>(path: string, content: string): Promise<T> {
  const response = await fetch(base + path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content })
  });
  if (!response.ok) {
    const body: unknown = await response.json().catch(() => null);
    const message = body && typeof body === "object" && "error" in body
      ? String(body.error) : "HTTP " + response.status;
    throw new Error(message);
  }
  return response.json() as Promise<T>;
}


export interface MediaCategory { id: string; name: string }
export interface MediaItem {
  id: string; name: string; categoryId: string | null; categoryName: string | null;
  poster: string | null; remarks: string | null; year: string | null; folder?: boolean; action?: string | null;
}
export interface MediaEpisode { name: string; playable: boolean }
export interface MediaLine { name: string; episodes: MediaEpisode[] }
export interface MediaPage {
  categories: MediaCategory[]; items: MediaItem[]; total: number;
  page: number; pageSize: number; hasMore: boolean; provider: string;
}
export interface MediaDetail {
  item: MediaItem; description: string | null; director: string | null;
  actors: string | null; lines: MediaLine[]; provider: string;
}
export interface MediaPlayback { url: string; name: string; lineName: string; provider: string; headers?: Record<string, string>; subtitles?: PlaybackResource[]; danmaku?: PlaybackResource[] }
export interface MediaQuery {
  content: string; categoryId?: string; query?: string; vodId?: string;
  page?: number; pageSize?: number; lineIndex?: number; episodeIndex?: number;
}

/** A stateless JSON fixture request; this does not grant any URL-fetch permissions. */
export async function postMedia<T>(path: string, body: MediaQuery): Promise<T> {
  const response = await fetch(base + path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!response.ok) {
    const error: unknown = await response.json().catch(() => null);
    const reason = error && typeof error === "object" && "error" in error
      ? String(error.error) : "HTTP " + response.status;
    throw new Error(reason);
  }
  return response.json() as Promise<T>;
}

export interface PlaybackResource { name: string; url: string; lang?: string | null }
export interface SubscriptionSite { key: string; name: string; type: number; searchable: boolean; hidden: boolean; support: string }
export interface SubscriptionDocument { content: string; url: string; sites: SubscriptionSite[]; depots: {name: string; url: string}[]; liveCount: number; warnings: string[] }
export async function requestJson<T>(path: string, body: unknown, signal?: AbortSignal): Promise<T> {
  const response = await fetch(base + path, { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body), signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(20000)]) : AbortSignal.timeout(20000) });
  if (!response.ok) {
    const data: unknown = await response.json().catch(() => null);
    throw new Error(data && typeof data === "object" && "error" in data ? String(data.error) : "HTTP " + response.status);
  }
  return response.json() as Promise<T>;
}
