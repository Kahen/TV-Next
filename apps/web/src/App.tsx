import { useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";
import { postText } from "./api";
import type { Channel, ConfigPreview, PlaylistResult } from "./api";

function validMediaUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return (url.protocol === "http:" || url.protocol === "https:") && !url.username && !url.password;
  } catch {
    return false;
  }
}

export default function App() {
  const [tab, setTab] = useState<"playlist" | "config">("playlist");
  const [rawText, setRawText] = useState("");
  const [configText, setConfigText] = useState("");
  const [channels, setChannels] = useState<Channel[]>([]);
  const [preview, setPreview] = useState<ConfigPreview | null>(null);
  const [selected, setSelected] = useState<Channel | null>(null);
  const [manualUrl, setManualUrl] = useState("");
  const [filter, setFilter] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [playerError, setPlayerError] = useState("");
  const videoRef = useRef<HTMLVideoElement | null>(null);

  const groups = useMemo(() => [...new Set(channels.map((c) => c.group))], [channels]);
  const visible = useMemo(() => channels.filter((c) =>
    (c.name + " " + c.group).toLowerCase().includes(filter.trim().toLowerCase())), [channels, filter]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.pause();
    video.removeAttribute("src");
    video.load();
    setPlayerError("");
    if (!selected) return;
    const url = selected.url;
    if (!validMediaUrl(url)) {
      setPlayerError("媒体地址无效。只支持 HTTP(S) URL。");
      return;
    }
    const isHls = new URL(url).pathname.toLowerCase().endsWith(".m3u8");
    let hls: Hls | null = null;
    if (isHls && video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = url;
    } else if (isHls && Hls.isSupported()) {
      hls = new Hls({ enableWorker: true });
      hls.loadSource(url);
      hls.attachMedia(video);
      hls.on(Hls.Events.ERROR, (_, detail) => {
        if (detail.fatal) setPlayerError("HLS 播放失败，请检查源地址、格式和跨域限制。");
      });
    } else if (isHls) {
      setPlayerError("当前浏览器不支持该 HLS 视频。");
    } else {
      video.src = url;
    }
    const onError = () => setPlayerError("播放失败：浏览器不支持此格式或视频源不可访问。");
    video.addEventListener("error", onError);
    return () => {
      video.removeEventListener("error", onError);
      if (hls) hls.destroy();
      video.pause();
      video.removeAttribute("src");
      video.load();
    };
  }, [selected]);

  async function importPlaylist() {
    setBusy(true);
    setError("");
    try {
      const parsed = await postText<PlaylistResult>("/api/v1/playlists/parse", rawText);
      setChannels(parsed.channels);
      setSelected(null);
      if (!parsed.total) setError("未找到可播放的 HTTP(S) 频道。");
    } catch (e) {
      setError(e instanceof Error ? e.message : "导入失败");
    } finally {
      setBusy(false);
    }
  }

  async function inspectConfig() {
    setBusy(true);
    setError("");
    try {
      setPreview(await postText<ConfigPreview>("/api/v1/configs/inspect", configText));
    } catch (e) {
      setError(e instanceof Error ? e.message : "配置解析失败");
    } finally {
      setBusy(false);
    }
  }

  function openManual() {
    if (!validMediaUrl(manualUrl)) {
      setError("请输入完整的 HTTP(S) 地址，且不要在 URL 中嵌入用户名或密码。");
      return;
    }
    setError("");
    setSelected({ name: "自定义播放地址", group: "Manual", url: manualUrl.trim() });
  }

  async function importFile(file: File | undefined) {
    if (!file) return;
    setError("");
    if (file.size > 1_048_576) {
      setError("文件不可超过 1 MiB。");
      return;
    }
    const content = await file.text();
    if (tab === "playlist") setRawText(content);
    else setConfigText(content);
  }

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark">▶</span><div><strong>TV-Next</strong><small>Personal media workspace</small></div></div>
        <p className="side-heading">WORKSPACE</p>
        <button className={tab === "playlist" ? "nav active" : "nav"} onClick={() => { setTab("playlist"); setError(""); }}>☷ <span>播放列表</span></button>
        <button className={tab === "config" ? "nav active" : "nav"} onClick={() => { setTab("config"); setError(""); }}>⚙ <span>配置检查</span></button>
        <div className="side-bottom"><p>Phase 0 · Preview</p><small>支持用户自有媒体及授权资源。不内置内容源。</small></div>
      </aside>
      <main>
        <header><div><p className="eyebrow">TV-NEXT / PLAYER</p><h1>你的媒体，随处播放。</h1><p className="subtitle">导入播放列表，或直接粘贴媒体 URL。iOS 与更多功能正在规划中。</p></div><span className="tag">EARLY BUILD</span></header>
        {error && <div className="alert" role="alert">{error}</div>}
        <section className="player-card">
          <div className="player-header"><span className="small-dot" /> {selected?.name || "尚未选择媒体"} <span className="player-type">HTTP(S) · HLS / MP4</span></div>
          <video ref={videoRef} controls playsInline preload="metadata" aria-label="视频播放器" />
          {playerError && <p className="player-error" role="alert">{playerError}</p>}
        </section>
        <div className="quick-play"><label htmlFor="manual-url">快速播放</label><div className="inline-controls"><input id="manual-url" type="url" placeholder="https://example.org/video.m3u8" value={manualUrl} onChange={(e) => setManualUrl(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") openManual(); }}/><button className="primary" onClick={openManual}>播放 URL →</button></div></div>
        <div className="section-heading"><h2>{tab === "playlist" ? "导入 M3U 播放列表" : "检查 FongMi JSON 配置"}</h2><span>{tab === "playlist" ? channels.length + " CHANNELS" : "STATIC INSPECTION ONLY"}</span></div>
        <section className="panel">
          <p className="hint">{tab === "playlist" ? "粘贴 #EXTM3U 文本，或选择本地 .m3u/.txt 文件。不会主动访问播放列表中的 URL。" : "仅检查 sites、lives 与 spider 字段，不会执行任何 Spider 代码。"}</p>
          <textarea aria-label={tab === "playlist" ? "M3U 内容" : "JSON 配置内容"} spellCheck={false} rows={7} value={tab === "playlist" ? rawText : configText} onChange={(e) => tab === "playlist" ? setRawText(e.target.value) : setConfigText(e.target.value)} placeholder={tab === "playlist" ? "#EXTM3U\n#EXTINF:-1 group-title=\"Demo\",My Channel\nhttps://example.org/stream.m3u8" : "{\"sites\":[],\"lives\":[]}"}/>
          <div className="panel-actions"><label className="file-picker">选择文件<input type="file" accept=".m3u,.m3u8,.txt,.json,text/plain,application/json" onChange={(e) => { void importFile(e.target.files?.[0]); e.target.value = ""; }}/></label><button disabled={busy} className="primary" onClick={() => void (tab === "playlist" ? importPlaylist() : inspectConfig())}>{busy ? "处理中…" : tab === "playlist" ? "解析播放列表" : "检查配置"}</button></div>
        </section>
        {tab === "playlist" && channels.length > 0 && <section className="results"><div className="section-heading"><h2>频道列表</h2><span>{groups.length} GROUPS</span></div><input className="filter-input" placeholder="按频道名称或分组搜索…" value={filter} onChange={(e) => setFilter(e.target.value)}/><div className="channel-list">{visible.map((channel, index) => <button className={selected === channel ? "channel selected" : "channel"} key={channel.url + index} onClick={() => setSelected(channel)}><span className="channel-avatar">▶</span><span className="channel-name"><strong>{channel.name}</strong><small>{channel.group}</small></span><span className="channel-arrow">↗</span></button>)}</div></section>}
        {tab === "config" && preview && <section className="results"><div className="section-heading"><h2>配置概况</h2><span>NO CODE EXECUTION</span></div><div className="stats"><div><strong>{preview.sites.length}</strong><small>显示站点（最多 1000）</small></div><div><strong>{preview.liveGroupCount}</strong><small>直播分组</small></div><div><strong>{preview.spiderDeclared ? "Yes" : "No"}</strong><small>声明 Spider</small></div></div><div className="channel-list">{preview.sites.map((site, i) => <div className="channel" key={site.key + i}><span className="channel-avatar">◈</span><span className="channel-name"><strong>{site.name || site.key || "Unnamed"}</strong><small>type {site.type ?? "unknown"} · {site.key}</small></span></div>)}</div></section>}
        <footer>TV-Next is an independent implementation. Media availability, formats and permissions depend on the provider and browser. © 2026 TV-Next</footer>
      </main>
    </div>
  );
}
