import { useState } from "react";
import { epgChannelsFromPlaylist, formatProgrammeRange } from "./epg";
import type { EpgGuideResponse } from "./epg";
import type { Channel } from "./api";
import { validMediaUrl } from "./library";

const MAX_XML_BYTES = 2_097_152;

export default function EpgGuide({ channels, onPlay }: {
  channels: Channel[];
  onPlay: (channel: Channel) => void;
}) {
  const [xml, setXml] = useState("");
  const [hours, setHours] = useState(12);
  const [guide, setGuide] = useState<EpgGuideResponse | null>(null);
  const [filter, setFilter] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const shown = guide?.channels.map((item, index) => ({ item, channel: channels[index] }))
    .filter(({ item }) => item.name.toLowerCase().includes(filter.toLowerCase()));

  async function loadFile(file: File | undefined) {
    if (!file) return;
    if (file.size === 0 || file.size > MAX_XML_BYTES) {
      setError("XMLTV 必须是 1 B 至 2 MiB 的 UTF-8 文件。");
      return;
    }
    try {
      const text = await file.text();
      if (text.length > MAX_XML_BYTES) throw new Error("XMLTV 内容超过 2 MiB。");
      setXml(text);
      setGuide(null);
      setError("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "读取 XMLTV 失败");
    }
  }

  async function loadGuide() {
    if (!xml.trim() || xml.length > MAX_XML_BYTES) {
      setError("粘贴或导入有效的 XMLTV 文本（不超过 2 MiB）。");
      return;
    }
    if (!channels.length) {
      setError("请先在“播放列表”导入含频道的 M3U，再导入相应 XMLTV。");
      return;
    }
    setBusy(true);
    setError("");
    setGuide(null);
    try {
      const res = await fetch((import.meta.env.VITE_API_BASE_URL || "") + "/api/v1/epg/guide", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          xml,
          channels: epgChannelsFromPlaylist(channels),
          hours
        })
      });
      const payload: unknown = await res.json().catch(() => null);
      if (!res.ok) {
        const message = payload && typeof payload === "object" && "error" in payload
          ? String(payload.error) : "HTTP " + res.status;
        throw new Error(message);
      }
      setGuide(payload as EpgGuideResponse);
    } catch (e) {
      setError(e instanceof Error ? e.message : "节目表解析失败");
    } finally {
      setBusy(false);
    }
  }

  return <section className="results epg-panel">
    <div className="section-heading">
      <h2>直播节目表 · XMLTV</h2>
      <span>P2 · STATIC GUIDE</span>
    </div>
    <p className="hint">导入你有权使用的 XMLTV 文件或粘贴内容。按 M3U 的 tvg-id 优先匹配，再尝试唯一频道名称；服务端只解析 XML，不会自动获取节目表网址。</p>
    <div className="epg-toolbar">
      <label className="file-picker">选择 XMLTV 文件
        <input type="file" accept=".xml,.xmltv,application/xml,text/xml" onChange={(e) => {
          void loadFile(e.target.files?.[0]); e.target.value = "";
        }} />
      </label>
      <label>查看未来
        <select value={hours} onChange={(e) => setHours(Number(e.target.value))}>
          <option value={6}>6 小时</option>
          <option value={12}>12 小时</option>
          <option value={24}>24 小时</option>
          <option value={48}>48 小时</option>
        </select>
      </label>
      <button className="primary" disabled={busy} onClick={() => void loadGuide()}>
        {busy ? "匹配中…" : "解析节目表"}
      </button>
    </div>
    <textarea aria-label="XMLTV 内容" spellCheck={false} rows={5}
      placeholder={'<?xml version="1.0" encoding="UTF-8"?>\n<tv><channel id="example"><display-name>示例频道</display-name></channel></tv>'}
      value={xml} onChange={(e) => { setXml(e.target.value); setGuide(null); }}
    />
    <p className="hint">目前媒体库 {channels.length} 个频道，每次最多匹配前 300 个。预览不会下载 XML 中的台标，也不会缓存节目表。</p>
    {error && <p className="alert" role="alert">{error}</p>}
    {guide && <>
      <div className="section-heading">
        <h2>匹配结果：{guide.matchedChannels} / {guide.totalChannels}</h2>
        <span>{hours}H WINDOW</span>
      </div>
      <input className="filter-input" aria-label="筛选节目表频道"
        placeholder="按频道名称筛选…" value={filter} onChange={(e) => setFilter(e.target.value)} />
      <div className="epg-entries">
        {shown?.map(({ item, channel }, index) =>
          <div className="epg-entry" key={(channel?.url || item.name) + index}>
            <div className="epg-entry-header">
              <div>
                <strong>{item.name}</strong>
                <small>{item.matchType === "id" ? "tvg-id 匹配" :
                  item.matchType === "name" ? "名称匹配" : "未匹配节目表"}</small>
              </div>
              {channel && validMediaUrl(channel.url) && <button className="secondary" onClick={() => onPlay(channel)}>
                播放频道
              </button>}
            </div>
            {item.current
              ? <div className="epg-current">
                  <p><strong>正在播：</strong>{item.current.title}
                    <small> {formatProgrammeRange(item.current.start, item.current.stop)}</small></p>
                  {item.current.description && <p className="epg-description">{item.current.description}</p>}
                </div>
              : <p className="hint">当前时间没有节目数据。</p>}
            {item.upcoming.length > 0 && <div className="epg-upcoming">
              {item.upcoming.map((next, i) => <div key={i}>
                <time>{formatProgrammeRange(next.start, next.stop)}</time><span>{next.title}</span>
              </div>)}
            </div>}
          </div>)}
      </div>
      {guide.warnings.map((warning, index) => <p className="hint" key={index}>解析提示：{warning}</p>)}
    </>}
  </section>;
}
