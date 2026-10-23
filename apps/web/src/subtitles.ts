/** Converts the common text-only SRT subset into browser WebVTT.
 * Styling/ASS/SSA and malformed legacy encodings are not yet supported.
 */
export function toWebVtt(text: string, filename: string): string {
  if (!text.trim() || text.length > 1_048_576) throw new Error("字幕必须为 1 B 至 1 MiB 的 UTF-8 文本。");
  const normalized = text.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
  if (filename.toLowerCase().endsWith(".vtt") || /^\s*WEBVTT(?:[ \t\r\n]|$)/.test(normalized)) {
    if (!/^\s*WEBVTT(?:[ \t\r\n]|$)/.test(normalized)) throw new Error("VTT 文件缺少 WEBVTT 标识。");
    return normalized;
  }
  if (!filename.toLowerCase().endsWith(".srt")) throw new Error("仅支持 UTF-8 SRT / WebVTT 字幕文件。");
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
