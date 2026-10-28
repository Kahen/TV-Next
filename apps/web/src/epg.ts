import type { Channel } from "./api";

export interface EpgProgram {
  start: string;
  stop: string;
  title: string;
  description: string | null;
}
export interface EpgChannel {
  id: string | null;
  name: string;
  matchedChannelId: string | null;
  matchType: "id" | "name" | "none";
  current: EpgProgram | null;
  upcoming: EpgProgram[];
  previous?: EpgProgram[];
}
export interface EpgGuideResponse {
  generatedAt: string;
  until: string;
  totalChannels: number;
  matchedChannels: number;
  channels: EpgChannel[];
  warnings: string[];
}
export interface EpgGuideRequest {
  xml: string;
  channels: { id: string | null; name: string }[];
  hours: number;
  at?: string;
}

export function epgChannelsFromPlaylist(channels: Channel[]): EpgGuideRequest["channels"] {
  return channels.slice(0, 300).map((channel) => ({
    id: channel.tvgId?.trim() || null,
    name: channel.name.trim()
  }));
}

export function formatProgrammeTime(raw: string, locale = "zh-CN"): string {
  const date = new Date(raw);
  if (!Number.isFinite(date.getTime())) return "时间无效";
  return new Intl.DateTimeFormat(locale, {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false
  }).format(date);
}

export function formatProgrammeRange(start: string, stop: string): string {
  return formatProgrammeTime(start) + " – " + formatProgrammeTime(stop);
}
