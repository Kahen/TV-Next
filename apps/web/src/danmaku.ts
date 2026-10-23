export interface DanmakuComment { time: number; mode: 1 | 4 | 5 | 6; color: string; size: number; text: string }
export interface DanmakuSource { name: string; url: string }
const LIMIT = 20_000;
/** FongMi DanmakuData: XML p=time(seconds),mode,size,color,...; dandanplay comments are accepted too. */
export function parseDanmaku(text: string): DanmakuComment[] {
  if (new TextEncoder().encode(text).length > 2_097_152) throw new Error("弹幕文件最多 2 MiB");
  const output: DanmakuComment[] = [];
  function add(p: string, message: unknown, dandan = false) {
    if (output.length >= LIMIT || typeof message !== "string") return;
    const values = p.split(",");
    const time = Number(values[0]), mode = Number(values[1]);
    const color = Number(values[dandan ? 2 : 3]), size = dandan ? 25 : Number(values[2]);
    if (!Number.isFinite(time) || time < 0 || time > 604800 || ![1, 4, 5, 6].includes(mode) ||
      !Number.isInteger(color) || color < 0 || color > 0xffffff || !Number.isFinite(size)) return;
    const content = message.replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "").trim().slice(0, 300);
    if (content) output.push({ time, mode: mode as DanmakuComment["mode"], color: "#" + color.toString(16).padStart(6, "0"), size: Math.max(12, Math.min(48, size)), text: content });
  }
  if (text.trim().startsWith("<")) {
    if (/<!DOCTYPE|<!ENTITY/i.test(text)) throw new Error("弹幕 XML 不允许 DTD 或外部实体");
    const doc = new DOMParser().parseFromString(text, "application/xml");
    if (doc.querySelector("parsererror")) throw new Error("弹幕 XML 无效");
    const nodes = doc.querySelectorAll("d[p]");
    if (nodes.length > LIMIT) throw new Error("弹幕数量最多 20000 条");
    nodes.forEach(node => add(node.getAttribute("p") || "", node.textContent));
  } else {
    const root: unknown = JSON.parse(text);
    const comments = Array.isArray(root) ? root : root && typeof root === "object" && "comments" in root ? (root as {comments: unknown}).comments : null;
    if (!Array.isArray(comments) || comments.length > LIMIT) throw new Error("弹幕 JSON 需要 comments 数组，最多 20000 条");
    for (const row of comments) {
      if (row && typeof row === "object" && typeof row.p === "string") add(row.p, row.m ?? row.text, true);
    }
  }
  return output.sort((a, b) => a.time - b.time);
}
export interface ScheduledComment extends DanmakuComment { lane: number; width: number; end: number }
/** Lane placement is computed from media timestamps, so pause, seek and speed changes stay synchronized. */
export function scheduleDanmaku(comments: DanmakuComment[], width: number, lanes: number, duration: number,
  measure: (text: string) => number): ScheduledComment[] {
  const scrolling: (ScheduledComment | undefined)[] = Array(lanes);
  const fixedTop: number[] = Array(lanes).fill(-Infinity), fixedBottom = [...fixedTop];
  const output: ScheduledComment[] = [];
  for (const item of comments) {
    const textWidth = Math.max(1, measure(item.text));
    let lane = -1;
    if (item.mode === 4 || item.mode === 5) {
      const available = item.mode === 4 ? fixedBottom : fixedTop;
      lane = available.findIndex(end => end <= item.time);
      if (lane >= 0) available[lane] = item.time + duration;
    } else {
      lane = scrolling.findIndex(prev => !prev || prev.end <= item.time || prev.mode === item.mode &&
        item.time - prev.time >= Math.max(prev.width / ((width + prev.width) / duration), duration - width / ((width + textWidth) / duration)));
    }
    if (lane < 0) continue;
    const scheduled = { ...item, width: textWidth, lane, end: item.time + duration };
    output.push(scheduled);
    if (item.mode === 1 || item.mode === 6) scrolling[lane] = scheduled;
  }
  return output;
}
