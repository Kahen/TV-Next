import { useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";
import { postText } from "./api";
import type { Channel, ConfigPreview, PlaylistResult } from "./api";
import {
  addRecent, emptyLibrary, loadLibrary, normalizeLibrary, saveLibrary,
  setPosition, toggleFavorite, validMediaUrl
} from "./library";
import type { LibraryState } from "./library";

type Tab = "playlist" | "config";
type Collection = "all" | "favorites" | "recent";

export default function App() {
  const [tab, setTab] = useState<Tab>("playlist");
  const [collection, setCollection] = useState<Collection>("all");
  const [rawText, setRawText] = useState("");
  const [configText, setConfigText] = useState("");
  const [library, setLibrary] = useState<LibraryState>(loadLibrary);
  const [preview, setPreview] = useState<ConfigPreview | null>(null);
  const [selected, setSelected] = useState<Channel | null>(null);
  const [manualUrl, setManualUrl] = useState("");
  const [filter, setFilter] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [playerError, setPlayerError] = useState("");
  const [storageWarning, setStorageWarning] = useState("");
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const libraryRef = useRef(library);
  libraryRef.current = library;
  const channels = library.channels;

  useEffect(() => {
    const ok = saveLibrary(library);
    setStorageWarning(ok ? "" : "浏览器没有保存数据，可能处于无痕模式或存储配额不足。");
  }, [library]);

  const groups = useMemo(() => [...new Set(channels.map((c) => c.group))], [channels]);
  const displayed = useMemo(() => {
    const byUrl = new Map<string, Channel>();
    for (const channel of [...channels, ...library.recent.map((entry) => entry.channel)]) {
      byUrl.set(channel.url, channel);
    }
    const items = collection === "all" ? channels :
      collection === "favorites" ? library.favorites.flatMap((url) => {
        const item = byUrl.get(url);
        return item ? [item] : [];
      }) : library.recent.map((entry) => entry.channel);
    const query = filter.trim().toLowerCase();
    return items.filter((item) => (item.name + " " + item.group).toLowerCase().includes(query));
  }, [channels, library.favorites, library.recent, collection, filter]);

  function playChannel(channel: Channel) {
    if (!validMediaUrl(channel.url)) {
      setError("媒体 URL 无效或包含不允许的凭据。");
      return;
    }
    setError("");
    setSelected(channel);
    setLibrary((state) => addRecent(state, channel));
  }

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.pause();
    video.removeAttribute("src");
    video.load();
    setPlayerError("");
    if (!selected || !validMediaUrl(selected.url)) return;
    const url = selected.url;
    const isHls = new URL(url).pathname.toLowerCase().endsWith(".m3u8");
    let hls: Hls | null = null;
    let lastSavedAt = 0;

    const remember = (force: boolean) => {
      if (!Number.isFinite(video.duration) || !Number.isFinite(video.currentTime)) return;
      const now = Date.now();
      if (!force && now - lastSavedAt < 8000) return;
      lastSavedAt = now;
      setLibrary((state) => setPosition(state, url, video.currentTime, video.duration));
    };
    const resume = () => {
      const position = libraryRef.current.positions[url];
      if (position && Number.isFinite(video.duration) && video.duration - position > 15) {
        try { video.currentTime = position; } catch { /* non-seekable stream */ }
      }
    };
    const onError = () => setPlayerError("播放失败：媒体地址不可访问、跨域限制或编解码不兼容。");
    const onTimeUpdate = () => remember(false);
    const onPause = () => remember(true);
    const onEnded = () => {
      if (Number.isFinite(video.duration)) {
        setLibrary((state) => setPosition(state, url, video.duration, video.duration));
      }
    };

    video.addEventListener("loadedmetadata", resume);
    video.addEventListener("error", onError);
    video.addEventListener("timeupdate", onTimeUpdate);
    video.addEventListener("pause", onPause);
    video.addEventListener("ended", onEnded);

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

    return () => {
      remember(true);
      video.removeEventListener("loadedmetadata", resume);
      video.removeEventListener("error", onError);
      video.removeEventListener("timeupdate", onTimeUpdate);
      video.removeEventListener("pause", onPause);
      video.removeEventListener("ended", onEnded);
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
      if (parsed.total > 1500) {
        setError("本地媒体库最多保留前 1500 个频道，可通过搜索或分组管理。");
      } else if (!parsed.total) {
        setError("未找到可播放的 HTTP(S) 频道。");
      }
      setLibrary((state) => normalizeLibrary({ ...state, channels: parsed.channels }));
      setSelected(null);
      setCollection("all");
      setFilter("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "导入失败");
    } finally {
      setBusy(false);
    }
  }

  async function inspectConfig() {
    setBusy(true);
    setError("");
    try {
      setPreview(await postText<ConfigPreview>("/api/v1/configs/inspect", configText));
    } catch (err) {
      setError(err instanceof Error ? err.message : "配置解析失败");
    } finally {
      setBusy(false);
    }
  }

  function openManual() {
    const url = manualUrl.trim();
    if (!validMediaUrl(url)) {
      setError("请输入完整的 HTTP(S) 地址，且不要在 URL 中嵌入用户名或密码。");
      return;
    }
    playChannel({ name: "自定义播放地址", group: "Manual", url });
  }

  async function importFile(file: File | undefined) {
    if (!file) return;
    setError("");
    if (file.size > 1_048_576) {
      setError("文件不可超过 1 MiB。");
      return;
    }
    try {
      const content = await file.text();
      if (tab === "playlist") setRawText(content);
      else setConfigText(content);
    } catch {
      setError("无法读取所选文件。");
    }
  }

  function resetLibrary() {
    if (!window.confirm("清空当前浏览器内的频道、收藏、最近播放及进度？此操作不可撤销。")) return;
    setSelected(null);
    setLibrary(emptyLibrary());
    setRawText("");
    setFilter("");
  }

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark">▶</span><div><strong>TV-Next</strong><small>Personal media workspace</small></div></div>
        <p className="side-heading">LIBRARY</p>
        <button className={tab === "playlist" && collection === "all" ? "nav active" : "nav"} onClick={() => { setTab("playlist"); setCollection("all"); setError(""); }}>☷ <span>播放列表</span></button>
        <button className={tab === "playlist" && collection === "favorites" ? "nav active" : "nav"} onClick={() => { setTab("playlist"); setCollection("favorites"); setError(""); }}>☆ <span>我的收藏</span> <small>{library.favorites.length}</small></button>
        <button className={tab === "playlist" && collection === "recent" ? "nav active" : "nav"} onClick={() => { setTab("playlist"); setCollection("recent"); setError(""); }}>◷ <span>最近播放</span></button>
        <p className="side-heading">TOOLS</p>
        <button className={tab === "config" ? "nav active" : "nav"} onClick={() => { setTab("config"); setError(""); }}>⚙ <span>配置检查</span></button>
        <div className="side-bottom"><p>Phase 1 · Local library</p><small>资料仅保存在此浏览器。不会自动同步到服务器。</small></div>
      </aside>
      <main>
        <header><div><p className="eyebrow">TV-NEXT / PLAYER</p><h1>你的媒体，随处播放。</h1><p className="subtitle">M3U 频道 · 收藏 · 最近播放 · 点播断点续播</p></div><span className="tag">P1 PREVIEW</span></header>
        {error && <div className="alert" role="alert">{error}</div>}
        {storageWarning && <div className="alert" role="status">{storageWarning}</div>}
        <section className="player-card">
          <div className="player-header"><span className="small-dot" /> {selected?.name || "尚未选择媒体"} <span className="player-type">HTTP(S) · HLS / MP4</span></div>
          <video ref={videoRef} controls playsInline preload="metadata" aria-label="视频播放器" />
          {playerError && <p className="player-error" role="alert">{playerError}</p>}
          {selected && <div className="player-actions">
            <button className="secondary" onClick={() => setLibrary((state) => toggleFavorite(state, selected.url))}>
              {library.favorites.includes(selected.url) ? "★ 取消收藏" : "☆ 收藏此频道"}
            </button>
            <label>播放速度 <select defaultValue="1" onChange={(event) => { if (videoRef.current) videoRef.current.playbackRate = Number(event.target.value); }}>
              <option value="0.75">0.75×</option><option value="1">1×</option><option value="1.25">1.25×</option><option value="1.5">1.5×</option><option value="2">2×</option>
            </select></label>
            {library.positions[selected.url] && <span className="resume-note">已保存进度 {Math.floor(library.positions[selected.url] / 60)} 分钟</span>}
          </div>}
        </section>
        <div className="quick-play"><label htmlFor="manual-url">快速播放</label><div className="inline-controls"><input id="manual-url" type="url" placeholder="https://example.org/video.m3u8" value={manualUrl} onChange={(e) => setManualUrl(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") openManual(); }}/><button className="primary" onClick={openManual}>播放 URL →</button></div></div>
        {tab === "config" ? <>
          <div className="section-heading"><h2>检查 FongMi JSON 配置</h2><span>STATIC INSPECTION ONLY</span></div>
          <section className="panel">
            <p className="hint">只展示站点、直播分组及 Spider 声明，不会运行 Java/JS/Python 插件或获取远程内容。</p>
            <textarea aria-label="JSON 配置内容" rows={7} spellCheck={false} value={configText} onChange={(event) => setConfigText(event.target.value)} placeholder={'{"sites":[],"lives":[]}'}/>
            <div className="panel-actions"><label className="file-picker">选择 JSON 文件<input type="file" accept=".json,application/json,text/plain" onChange={(event) => { void importFile(event.target.files?.[0]); event.target.value = ""; }}/></label><button disabled={busy} className="primary" onClick={() => void inspectConfig()}>{busy ? "检查中…" : "检查配置"}</button></div>
          </section>
          {preview && <section className="results"><div className="section-heading"><h2>配置概况</h2><span>NO CODE EXECUTION</span></div><div className="stats"><div><strong>{preview.sites.length}</strong><small>站点预览（最多 1000）</small></div><div><strong>{preview.liveGroupCount}</strong><small>直播分组</small></div><div><strong>{preview.spiderDeclared ? "Yes" : "No"}</strong><small>声明 Spider</small></div></div><div className="channel-list">{preview.sites.map((site, i) => <div className="channel" key={site.key + i}><span className="channel-avatar">◈</span><span className="channel-name"><strong>{site.name || site.key || "Unnamed"}</strong><small>type {site.type ?? "unknown"} · {site.key}</small></span></div>)}</div></section>}
        </> : <>
          <div className="section-heading"><h2>导入 M3U 播放列表</h2><span>{channels.length} CHANNELS</span></div>
          <section className="panel">
            <p className="hint">导入 .m3u 或文本；新列表会替换当前频道，但不会清空收藏和历史。最多保存 1500 个频道。</p>
            <textarea aria-label="M3U 内容" spellCheck={false} rows={5} value={rawText} onChange={(event) => setRawText(event.target.value)} placeholder={'#EXTM3U\n#EXTINF:-1 group-title="Demo",My Channel\nhttps://example.org/stream.m3u8'}/>
            <div className="panel-actions"><label className="file-picker">选择 M3U 文件<input type="file" accept=".m3u,.txt,text/plain" onChange={(event) => { void importFile(event.target.files?.[0]); event.target.value = ""; }}/></label><button disabled={busy} className="primary" onClick={() => void importPlaylist()}>{busy ? "解析中…" : "导入频道"}</button></div>
          </section>
          <section className="results">
            <div className="section-heading"><h2>{collection === "favorites" ? "我的收藏" : collection === "recent" ? "最近播放" : "频道列表"}</h2><span>{collection === "all" ? groups.length + " GROUPS" : displayed.length + " ITEMS"}</span></div>
            <div className="library-toolbar"><input className="filter-input" aria-label="搜索频道" placeholder="按名称或分组搜索…" value={filter} onChange={(event) => setFilter(event.target.value)}/><button className="secondary danger" onClick={resetLibrary}>清空本地媒体库</button></div>
            {displayed.length === 0 && <p className="hint">{collection === "favorites" ? "还没有收藏的频道。" : collection === "recent" ? "还没有播放记录。" : "频道列表为空，请导入 M3U。"}</p>}
            <div className="channel-list">{displayed.map((channel, index) => <div className="channel-line" key={channel.url + index}>
              <button className={selected?.url === channel.url ? "channel selected" : "channel"} onClick={() => playChannel(channel)}>
                <span className="channel-avatar">▶</span><span className="channel-name"><strong>{channel.name}</strong><small>{channel.group}{library.positions[channel.url] ? " · 已保存播放进度" : ""}</small></span><span className="channel-arrow">↗</span>
              </button>
              <button className="favorite-toggle" aria-label={library.favorites.includes(channel.url) ? "取消收藏 " + channel.name : "收藏 " + channel.name} aria-pressed={library.favorites.includes(channel.url)} onClick={() => setLibrary((state) => toggleFavorite(state, channel.url))}>
                {library.favorites.includes(channel.url) ? "★" : "☆"}
              </button>
            </div>)}</div>
          </section>
        </>}
        <footer>仅限你有权使用的媒体。收藏和播放进度保存在当前浏览器，可随时清空；共享设备请注意隐私。© 2026 TV-Next</footer>
      </main>
    </div>
  );
}
