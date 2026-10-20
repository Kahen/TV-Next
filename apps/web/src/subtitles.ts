/** Converts the common text-only SRT subset into browser WebVTT.
 * Styling/ASS/SSA and malformed legacy encodings are not yet supported.
 */
export function toWebVtt(text: string, filename: string): string {
  if (!text.trim() || text.length > 1_048_576) throw new Error("字幕必须为 1 B 至 1 MiB 的 UTF-8 文本。");
  const normalized = text.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
  if (filename.toLowerCase().endsWith(".vtt") || /^\s*WEBVTT(?:[ \t]|$)/.test(normalized)) {
    if (!/^\s*WEBVTT(?:[ \t]|$)/.test(normalized)) throw new Error("VTT 文件缺少 WEBVTT 标识。");
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
