import type { Channel } from "./api";
import { validMediaUrl } from "./library";

/** Export a safe subset of locally saved streams as a portable UTF-8 M3U. */
export function exportM3u(channels: Channel[]): string {
  const escapeAttribute = (value: string) => value.replace(/[\r\n"]/g, " ").slice(0, 200);
  const escapeTitle = (value: string) => value.replace(/[\r\n]/g, " ").slice(0, 200);
  return "#EXTM3U\n" + channels.filter((channel) => validMediaUrl(channel.url))
    .map((channel) => {
      const name = escapeTitle(channel.name || "Unnamed");
      const group = escapeAttribute(channel.group || "Uncategorized");
      const tvg = channel.tvgId ? ' tvg-id="' + escapeAttribute(channel.tvgId) + '"' : "";
      return '#EXTINF:-1 group-title="' + group + '"' + tvg + "," + name + "\n" + channel.url + "\n";
    }).join("");
}
