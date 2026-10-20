export interface Channel {
  name: string;
  url: string;
  group: string;
  logo?: string | null;
  tvgId?: string | null;
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
