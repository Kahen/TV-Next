import { useEffect, useRef, useState } from "react";
import { requestJson } from "./api";
import type { Channel, LiveReplaySession } from "./api";
import type { HomeSession } from "./homeApi";
import { homeRequest } from "./homeApi";
import { mediaRelayAddress } from "./useMediaRelay";

export function timeshiftRange(channel: Channel, now = Date.now()): [number, number] | null {
  const s = channel.timeshift;
  if (!s || !Number.isSafeInteger(s.start) || !Number.isSafeInteger(s.window) || s.start <= 0 || s.start >= now || s.window <= 0 ||
      typeof s.url !== "string" || !/\{time\}|%7Btime%7D/i.test(s.url)) return null;
  return [Math.max(s.start, now - s.window), now];
}

function localDateValue(time: number): string {
  const date = new Date(time);
  return new Date(time - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 19);
}

export default function LiveReplayControls({ channel, session, onPlay, programme }: {
  channel: Channel; session: HomeSession | null; onPlay: (channel: Channel) => void;
  programme?: { start: string; stop: string; title: string };
}) {
  const [now, setNow] = useState(Date.now);
  const [time, setTime] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const pending = useRef<AbortController | null>(null);
  const generation = useRef(0);
  useEffect(() => {
    if (programme) return;
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [programme?.start]);
  useEffect(() => {
    generation.current++; pending.current?.abort(); setError(""); setBusy(false); setTime("");
    return () => { generation.current++; pending.current?.abort(); };
  }, [channel.url, session?.token, programme?.start, programme?.stop]);
  const range = timeshiftRange(channel, now);
  const catchup = !!programme && !!channel.catchup;
  if (!range && !catchup && !channel.replay) return null;

  async function replay(timestamp: number, stop?: number) {
    if (!session) { setError("请先登录家庭服务器以使用直播回放。"); return; }
    if (!Number.isSafeInteger(timestamp) || timestamp < 0 ||
        (timestamp !== 0 && stop === undefined && (!range || timestamp < range[0] || timestamp > Date.now()))) {
      setError("请选择提供方允许的回放时间。"); return;
    }
    pending.current?.abort(); const controller = new AbortController(); pending.current = controller;
    const id = ++generation.current; setBusy(true); setError("");
    try {
      const result = await requestJson<LiveReplaySession>("/api/v1/subscriptions/replay", {
        channel: { name: channel.name, url: channel.url, group: channel.group, headers: channel.headers || {}, timeshift: channel.timeshift, catchup: channel.catchup },
        time: timestamp, stop, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
      }, controller.signal, session.token);
      const address = mediaRelayAddress(result.path);
      if (!Number.isSafeInteger(result.expiresAt) || result.expiresAt <= Date.now()) throw new Error("回放会话已过期，请重新选择时间。");
      if (id !== generation.current || controller.signal.aborted) {
        void homeRequest("media/" + address.ticket + "/close", {}, session.token).catch(() => {}); return;
      }
      onPlay({ ...channel, replay: result });
    } catch (e) {
      if (id === generation.current && !controller.signal.aborted) setError(e instanceof Error ? e.message : "回放解析失败");
    } finally { if (id === generation.current) setBusy(false); }
  }

  return <div className="replay-controls" aria-label={programme ? "节目回看" : "直播时移"}>
    {!session && <p className="hint">登录家庭服务器后可使用直播回放。</p>}
    {range && !programme && <>
      <label>回放时间<input aria-label="回放时间" type="datetime-local" step="1" value={time}
        min={localDateValue(range[0])} max={localDateValue(range[1])} onChange={e => setTime(e.target.value)} /></label>
      <span className="hint">{new Date(range[0]).toLocaleString()} 至当前时间（本地时区）</span>
      <button disabled={!session || !time} onClick={() => void replay(new Date(time).getTime())}>播放所选时间</button>
    </>}
    {catchup && <button disabled={!session} onClick={() => void replay(Date.parse(programme!.start), Math.min(Date.parse(programme!.stop), Date.now()))}>
      回看 · {programme!.title}
    </button>}
    {!programme && <button disabled={!session} onClick={() => void replay(0)}>回到直播</button>}
    {busy && <><span role="status">正在解析回放…</span><button onClick={() => { generation.current++; pending.current?.abort(); setBusy(false); }}>取消回放请求</button></>}
    {error && <p role="alert">{error}</p>}
  </div>;
}
