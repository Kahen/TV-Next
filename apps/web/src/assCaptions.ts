/** A deliberately text-only subset of ASS/SSA [Events] Dialogue records.
 * Dialogue fields follow the declared Format order and Text must be last.
 * Overrides, animations, styling and screen coordinates are not interpreted.
 */
export function assToWebVtt(input: string): string {
  let events = false;
  let fields: string[] = [];
  const cues: string[] = [];
  for (const raw of input.replace(/\r\n?/g, "\n").split("\n")) {
    const line = raw.trim();
    if (/^\[[^\]]+\]$/.test(line)) {
      events = /^\[Events\]$/i.test(line);
      continue;
    }
    if (!events) continue;
    const fmt = /^Format:\s*(.*)$/i.exec(line);
    if (fmt) { fields = fmt[1].split(",").map(field => field.trim().toLowerCase()); continue; }
    const dialogue = /^Dialogue:\s*(.*)$/i.exec(line);
    if (!dialogue || fields.length < 3 || fields.at(-1) !== "text") continue;
    const startIndex = fields.indexOf("start"), endIndex = fields.indexOf("end");
    if (startIndex < 0 || endIndex < 0 || startIndex === endIndex) continue;
    let rest = dialogue[1];
    const cells: string[] = [];
    for (let i = 0; i < fields.length - 1; i++) {
      const comma = rest.indexOf(",");
      if (comma < 0) break;
      cells.push(rest.slice(0, comma).trim());
      rest = rest.slice(comma + 1);
    }
    if (cells.length !== fields.length - 1) continue;
    cells.push(rest);
    const start = parseAssTime(cells[startIndex]), end = parseAssTime(cells[endIndex]);
    if (start === null || end === null || end <= start) continue;
    const payload = cells[fields.length - 1]
      .replace(/\{\\[^{}]*\}/g, "")
      .replace(/\\[Nn]/g, "\n").replace(/\\h/g, "\u00a0")
      .trim().slice(0, 2000)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    if (!payload) continue;
    cues.push(formatAssTime(start) + " --> " + formatAssTime(end) + "\n" + payload);
    if (cues.length === 5000) break;
  }
  if (!cues.length) throw new Error("未找到可识别的 ASS/SSA 时间轴。");
  return "WEBVTT\n\n" + cues.join("\n\n") + "\n";
}
function parseAssTime(value: string): number | null {
  const match = /^(\d{1,2}):(\d{2}):(\d{2})\.(\d{1,2})$/.exec(value);
  if (!match) return null;
  const hour = Number(match[1]), minute = Number(match[2]), second = Number(match[3]);
  if (minute >= 60 || second >= 60) return null;
  const centiseconds = Number(match[4].padEnd(2, "0"));
  return ((hour * 60 + minute) * 60 + second) * 1000 + centiseconds * 10;
}
function formatAssTime(ms: number): string {
  const h = Math.floor(ms / 3_600_000), m = Math.floor(ms / 60_000) % 60;
  const s = Math.floor(ms / 1000) % 60, fraction = ms % 1000;
  return [h, m, s].map(n => String(n).padStart(2, "0")).join(":") + "." + String(fraction).padStart(3, "0");
}
