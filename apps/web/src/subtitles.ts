import { assToWebVtt } from "./assCaptions";

/** Converts decoded SRT and text-only ASS/SSA into browser WebVTT.
 * File decoding happens before conversion. ASS/SSA styling is omitted.
 */
export function toWebVtt(text: string, filename: string): string {
  if (!text.trim() || text.length > 1_048_576 || new TextEncoder().encode(text).byteLength > 1_048_576) throw new Error("字幕文本的 UTF-8 大小必须为 1 B 至 1 MiB。");
  const normalized = text.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
  if (filename.toLowerCase().endsWith(".vtt") || /^\s*WEBVTT(?:[ \t\r\n]|$)/.test(normalized)) {
    if (!/^\s*WEBVTT(?:[ \t\r\n]|$)/.test(normalized)) throw new Error("VTT 文件缺少 WEBVTT 标识。");
    return normalized;
  }
  if (/\.(ass|ssa)$/i.test(filename) || /^\s*\[(?:Script Info|Events)\]\s*$/mi.test(normalized)) return assToWebVtt(normalized);
  if (!filename.toLowerCase().endsWith(".srt")) throw new Error("仅支持 SRT / WebVTT / ASS / SSA 字幕文件。");
  const blocks = normalized.trim().split(/\n[ \t]*\n+/);
  const cues: string[] = [];
  const timestamp = /^(?:(\d{2}):)?(\d{2}):(\d{2})[,.](\d{3})[ \t]+-->[ \t]+(?:(\d{2}):)?(\d{2}):(\d{2})[,.](\d{3})(?:[ \t].*)?$/;
  for (const block of blocks) {
    const lines = block.split("\n");
    if (/^\d+$/.test(lines[0].trim())) lines.shift();
    if (lines.length < 2) continue;
    const match = timestamp.exec(lines[0].trim());
    if (!match) continue;
    const start = [(match[1] || "00"), match[2], match[3]].join(":") + "." + match[4];
    const end = [(match[5] || "00"), match[6], match[7]].join(":") + "." + match[8];
    const payload = lines.slice(1).join("\n").trim();
    if (payload) cues.push(start + " --> " + end + "\n" + payload);
  }
  if (!cues.length) throw new Error("未找到可识别的 SRT 时间轴。");
  return "WEBVTT\n\n" + cues.join("\n\n") + "\n";
}

export function isPlayableLocalMedia(file: File): boolean {
  if (file.size === 0) return false;
  const allowedExtensions = /\.(mp4|m4v|mov|webm|ogv|ogg|mp3|m4a|aac)$/i;
  return allowedExtensions.test(file.name) ||
    /^(video\/(mp4|quicktime|webm|ogg)|audio\/(mpeg|mp4|ogg|aac))$/.test(file.type);
}


/**
 * Adjusts timestamps of external WebVTT cues without mutating media playback.
 * A positive offset delays captions; cues entirely before t=0 are discarded.
 * NOTE/STYLE/REGION blocks and cue settings are left untouched.
 */
export function shiftWebVtt(vtt: string, offsetSeconds: number): string {
  if (!Number.isFinite(offsetSeconds) || offsetSeconds < -10 || offsetSeconds > 10) {
    throw new Error("字幕偏移范围为 -10 至 +10 秒。");
  }
  if (!offsetSeconds) return vtt;
  const milliseconds = Math.round(offsetSeconds * 1000);
  const clock = /^(\d{2,}:\d{2}(?::\d{2})?\.\d{3})\s+-->\s+(\d{2,}:\d{2}(?::\d{2})?\.\d{3})(.*)$/;
  function parse(value: string): number {
    const parts = value.split(":");
    const sec = Number(parts.pop());
    const minute = Number(parts.pop());
    const hour = parts.length ? Number(parts[0]) : 0;
    return ((hour * 60 + minute) * 60 + sec) * 1000;
  }
  function format(ms: number): string {
    const time = Math.max(0, Math.round(ms));
    const hour = Math.floor(time / 3_600_000);
    const minute = Math.floor(time / 60_000) % 60;
    const second = Math.floor(time / 1000) % 60;
    const fraction = time % 1000;
    return [hour, minute, second].map(x => String(x).padStart(2, "0")).join(":") +
      "." + String(fraction).padStart(3, "0");
  }
  return vtt.replace(/\r\n?/g, "\n").split(/\n[ \t]*\n+/).map((block) => {
    const lines = block.split("\n");
    const index = lines.findIndex(line => line.includes("-->"));
    if (index < 0) return block;
    const match = clock.exec(lines[index]);
    if (!match) return block;
    const start = parse(match[1]) + milliseconds;
    const end = parse(match[2]) + milliseconds;
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= 0) return "";
    lines[index] = format(start) + " --> " + format(Math.max(start + 1, end)) + match[3];
    return lines.join("\n");
  }).filter(Boolean).join("\n\n") + "\n";
}

/** Resolve a single picker selection without reading the media or any subtitle. */
export function localPlaybackFiles(files: File[]) {
  const subtitles: File[] = [];
  const media: File[] = [];
  for (const file of files) {
    if (/\.(srt|vtt|ass|ssa)$/i.test(file.name)) subtitles.push(file);
    else if (isPlayableLocalMedia(file)) media.push(file);
  }
  if (media.length !== 1) {
    throw new Error(media.length ? "一次只能打开一个媒体文件，可同时选择多份字幕。"
      : "请选择可由浏览器支持的本地 MP4 / MOV / WebM / OGG / 音频文件。");
  }
  if (files.length !== subtitles.length + 1) throw new Error("随片文件仅支持 SRT、VTT、ASS 和 SSA 字幕。");

  const stem = (name: string) => name.replace(/\.[^.]*$/, "").normalize("NFC").toLowerCase();
  const video = stem(media[0].name);
  const matches = subtitles.filter(file => stem(file.name) === video || stem(file.name).startsWith(video + "."));
  const candidates = matches.length ? matches : subtitles;
  candidates.sort((lhs, rhs) => {
    const exactFirst = Number(stem(rhs.name) === video) - Number(stem(lhs.name) === video);
    if (exactFirst) return exactFirst;
    const a = lhs.name.toLowerCase(), b = rhs.name.toLowerCase();
    return a < b ? -1 : a > b ? 1 : lhs.name.localeCompare(rhs.name);
  });
  return {media: media[0], subtitles: candidates};
}


export type CaptionFileEncoding = "unicode" | "gb18030";

export function decodeCaptionFile(bytes: Uint8Array, encoding: CaptionFileEncoding): string {
  if (bytes.length > 1_048_576) throw new Error("字幕文件不可超过 1 MiB。");
  const utf16le = bytes[0] === 0xff && bytes[1] === 0xfe;
  const utf16be = bytes[0] === 0xfe && bytes[1] === 0xff;
  const utf8bom = bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf;
  if (encoding === "gb18030" && (utf16le || utf16be || utf8bom)) {
    throw new Error("这份字幕含 Unicode 字节序标记，请选用 Unicode 编码。");
  }
  const charset = encoding === "gb18030" ? encoding : utf16le ? "utf-16le" : utf16be ? "utf-16be" : "utf-8";
  try {
    const text = new TextDecoder(charset, {fatal: true}).decode(bytes);
    if (!text.includes("\0")) return text;
  } catch {
    // Invalid input and unavailable platform decoders use the same actionable error.
  }
  throw new Error("字幕编码无效，请检查字幕文件并选择对应编码。");
}
