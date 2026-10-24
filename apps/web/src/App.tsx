import { useEffect, useMemo, useRef, useState } from "react";
import Hls from "hls.js";
import { postText, requestJson } from "./api";
import type { Channel, CatalogPreview, ConfigPreview, PlaylistResult } from "./api";
import {
  addRecent, emptyLibrary, loadLibrary, saveLibrary,
  replacePlaylistChannels, setPosition, toggleFavorite, validMediaUrl
} from "./library";
import type { LibraryState } from "./library";
import { isPlayableLocalMedia, shiftWebVtt, toWebVtt } from "./subtitles";
import { exportM3u } from "./playlistExport";
import MediaBrowser from "./MediaBrowser";
import HomeServerPanel from "./HomeServerPanel";
import { useRemoteControl } from "./useRemoteControl";
import { useMediaRelay } from "./useMediaRelay";
import { loadHomeSession, saveHomeSession } from "./homeApi";
import CloudBrowser from "./CloudBrowser";
import SubscriptionBrowser from "./SubscriptionBrowser";
import DanmakuOverlay, { defaultDanmakuSettings } from "./DanmakuOverlay";
import { parseDanmaku } from "./danmaku";
import type { DanmakuComment } from "./danmaku";
import "./media-style.css";
import EpgGuide from "./EpgGuide";
import "./epg-style.css";

type Tab = "playlist" | "config" | "media" | "epg" | "home";
type Collection = "all" | "favorites" | "recent";

export default function App() {
  const [danmaku, setDanmaku] = useState<DanmakuComment[]>([]);
  const [danmakuSettings, setDanmakuSettings] = useState(defaultDanmakuSettings);
  const [homeSession, setHomeSession] = useState(loadHomeSession);
  useEffect(() => saveHomeSession(homeSession), [homeSession]);
  const [tab, setTab] = useState<Tab>("playlist");
  const [collection, setCollection] = useState<Collection>("all");
  const [rawText, setRawText] = useState("");
  const [configText, setConfigText] = useState("");
  const [library, setLibrary] = useState<LibraryState>(loadLibrary);
  const [preview, setPreview] = useState<ConfigPreview | null>(null);
  const [catalog, setCatalog] = useState<CatalogPreview | null>(null);
  const [selected, setSelected] = useState<Channel | null>(null);
  const [manualUrl, setManualUrl] = useState("");
  const [filter, setFilter] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [playerError, setPlayerError] = useState("");
  const [localVideo, setLocalVideo] = useState<{ url: string; name: string } | null>(null);
  const [subtitleUrl, setSubtitleUrl] = useState<string | null>(null);
  const [subtitleOriginal, setSubtitleOriginal] = useState("");
  const [subtitleOffset, setSubtitleOffset] = useState(0);
  const [subtitleName, setSubtitleName] = useState("");
  const [storageWarning, setStorageWarning] = useState("");
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const relay=useMediaRelay(localVideo?null:selected,homeSession);
  const mediaKey = selected?.url ?? localVideo?.url;
  const mediaKeyRef = useRef(mediaKey); mediaKeyRef.current = mediaKey;
  const libraryRef = useRef(library);
  libraryRef.current = library;
  const channels = library.channels;
  const remoteState = useRemoteControl(homeSession,async packet=>{
    const video=videoRef.current;
    if(packet.type==="LOAD"){if(!packet.url||!validMediaUrl(packet.url))throw Error("无效的播放地址");playChannel({name:"远程媒体",url:packet.url,group:"Remote"});return;}
    if(!video)throw Error("播放器尚未就绪");
    if(packet.type==="PLAY"){await video.play();return;}
    if(packet.type==="PAUSE"){video.pause();return;}
    if(packet.type==="SEEK"){if(typeof packet.position!=="number"||!Number.isFinite(video.duration)||packet.position<0||packet.position>video.duration)throw Error("当前媒体无法跳转到该位置");video.currentTime=packet.position;}
  });

  // Object URLs are deliberately ephemeral and never written to the media library.
  useEffect(() => () => { if (localVideo) URL.revokeObjectURL(localVideo.url); }, [localVideo]);
  useEffect(() => () => { if (subtitleUrl) URL.revokeObjectURL(subtitleUrl); }, [subtitleUrl]);
  useEffect(() => {
    if (!subtitleOriginal) {
      setSubtitleUrl(null);
      return;
    }
    const shifted = shiftWebVtt(subtitleOriginal, subtitleOffset);
    setSubtitleUrl(URL.createObjectURL(new Blob([shifted], { type: "text/vtt" })));
  }, [subtitleOriginal, subtitleOffset]);

  useEffect(() => {
    const video = videoRef.current;
    if (video && subtitleUrl && video.textTracks.length) video.textTracks[0].mode = "showing";
  }, [subtitleUrl]);

  useEffect(() => {
    const ok = saveLibrary(library);
    setStorageWarning(ok ? "" : "浏览器没有保存数据，可能处于无痕模式或存储配额不足。");
  }, [library]);

  const groups = useMemo(() => [...new Set(channels.map((c) => c.group))], [channels]);
  const displayed = useMemo(() => {
    const byUrl = new Map<string, Channel>();
    for (const channel of [...library.recent.map((entry) => entry.channel), ...channels]) {
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
    if (channel.headersRequired) { setError("此频道的私密请求头未保存在媒体库，请重新加载订阅后播放。"); return; }
    setError("");
    setLocalVideo(null);
    setSelected(channel);
    setDanmaku([]); setSubtitleOriginal(""); setSubtitleName("");
    setLibrary((state) => addRecent(state, channel));
  }

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.pause();
    video.removeAttribute("src");
    video.load();
    setPlayerError("");
    if (!selected && !localVideo) return;
    const isLocal = !!localVideo;
    if(!isLocal&&relay.required&&!relay.url){setPlayerError(relay.error||"正在适配播放请求头…");return;}
    const url = localVideo?.url ?? relay.url ?? selected!.url;
    const positionKey=selected?.url ?? url;
    if (!isLocal && !validMediaUrl(url)) return;
    const isHls = !isLocal && (relay.hls || new URL(selected!.url).pathname.toLowerCase().endsWith(".m3u8"));
    let hls: Hls | null = null;
    let lastSavedAt = 0;

    const remember = (force: boolean) => {
      if (isLocal || !Number.isFinite(video.duration) || !Number.isFinite(video.currentTime)) return;
      const now = Date.now();
      if (!force && now - lastSavedAt < 8000) return;
      lastSavedAt = now;
      setLibrary((state) => setPosition(state, positionKey, video.currentTime, video.duration));
    };
    const resume = () => {
      if (isLocal) return;
      const position = libraryRef.current.positions[positionKey];
      if (position && Number.isFinite(video.duration) && video.duration - position > 15) {
        try { video.currentTime = position; } catch { /* non-seekable stream */ }
      }
    };
    const onError = () => setPlayerError("播放失败：媒体地址不可访问、跨域限制或编解码不兼容。");
    const onTimeUpdate = () => remember(false);
    const onPause = () => remember(true);
    const onEnded = () => {
      if (!isLocal && Number.isFinite(video.duration)) {
        setLibrary((state) => setPosition(state, positionKey, video.duration, video.duration));
      }
    };

    video.addEventListener("loadedmetadata", resume);
    video.addEventListener("error", onError);
    video.addEventListener("timeupdate", onTimeUpdate);
    video.addEventListener("pause", onPause);
    video.addEventListener("ended", onEnded);

    const playbackHeaders=relay.url?{}:selected?.headers||{};
    if (Object.keys(playbackHeaders).length && !(isHls && Hls.isSupported())) {
      setPlayerError("此来源要求额外请求头；请先登录家庭服务器，启用当前浏览器的媒体中转适配。");
    } else if (isHls && !Object.keys(playbackHeaders).length && video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = url;
    } else if (isHls && Hls.isSupported()) {
      hls = new Hls({ enableWorker: true, xhrSetup: (xhr) => { for (const [key, value] of Object.entries(playbackHeaders)) xhr.setRequestHeader(key, value); } });
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
  }, [selected, localVideo,relay.required,relay.url,relay.hls,relay.error]);

  function playLocalFile(file: File | undefined) {
    if (!file) return;
    if (!isPlayableLocalMedia(file)) {
      setError("请选择可由浏览器支持的本地 MP4 / MOV / WebM / OGG / 音频文件；本地 HLS、MKV 等格式可能不被支持。");
      return;
    }
    setError("");
    setSelected(null);
    setDanmaku([]); setSubtitleOriginal(""); setSubtitleName("");
    setLocalVideo({ url: URL.createObjectURL(file), name: file.name });
    // Browser object URLs do not survive refresh, and must never appear in recent/favorites.
  }

  async function importSubtitle(file: File | undefined) {
    if (!file) return;
    if (file.size > 1_048_576) {
      setError("字幕文件不可超过 1 MiB。");
      return;
    }
    try {
      const vtt = toWebVtt(await file.text(), file.name);
      setSubtitleOffset(0);
      setSubtitleOriginal(vtt);
      setSubtitleName(file.name);
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "无法读取字幕");
    }
  }

  async function loadSubtitleSource(url: string, name: string) {
    const key=mediaKey;
    try { const result=await requestJson<{content:string}>("/api/v1/resources/text",{url});if(key!==mediaKeyRef.current)return;setSubtitleOriginal(toWebVtt(result.content, /\.(srt|vtt|ass|ssa)$/i.test(name) ? name : (/\.(srt|vtt|ass|ssa)$/i.test(new URL(url).pathname) ? new URL(url).pathname : "remote.srt")));setSubtitleOffset(0);setSubtitleName(name); }
    catch(e){setError(e instanceof Error?e.message:"字幕加载失败");}
  }
  async function loadDanmakuFile(file: File) {
    try { if(file.size>2097152)throw new Error("弹幕最多 2 MiB");setDanmaku(parseDanmaku(await file.text()));setError(""); }
    catch(e) {setError(e instanceof Error?e.message:"弹幕导入失败");}
  }
  async function loadDanmakuSource(url: string) {
    const key=mediaKey;
    try { const result = await requestJson<{content:string}>("/api/v1/resources/text",{url});if(key!==mediaKeyRef.current)return;setDanmaku(parseDanmaku(result.content)); }
    catch(e) {setError(e instanceof Error?e.message:"弹幕加载失败");}
  }

  async function enterFullscreen() {
    const video = videoRef.current;
    if (!video) return;
    if (!video.parentElement?.requestFullscreen) {
      setPlayerError("此浏览器请使用视频原生的全屏按钮。");
      return;
    }
    try { await video.parentElement!.requestFullscreen(); } catch {
      setPlayerError("浏览器拒绝进入全屏，请检查权限和用户交互限制。");
    }
  }

  async function enterPictureInPicture() {
    const video = videoRef.current;
    if (!video || !document.pictureInPictureEnabled || !video.requestPictureInPicture) {
      setPlayerError("此浏览器不支持网页画中画，请使用视频原生控件。");
      return;
    }
    try { await video.requestPictureInPicture(); } catch {
      setPlayerError("画中画无法启动，请先播放视频并检查浏览器限制。");
    }
  }

  async function importPlaylist() {
    setBusy(true);
    setError("");
    try {
      const parsed = await postText<PlaylistResult>("/api/v1/playlists/parse", rawText);
      const decision = replacePlaylistChannels(libraryRef.current, parsed);
      if (decision.warning) setError(decision.warning);
      if (!decision.applied) return;
      setLibrary((state) => replacePlaylistChannels(state, parsed).state);
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
    setCatalog(null);
    setPreview(null);
    try {
      const [inspection, normalized] = await Promise.all([
        postText<ConfigPreview>("/api/v1/configs/inspect", configText),
        postText<CatalogPreview>("/api/v1/catalog/preview", configText)
      ]);
      setPreview(inspection);
      setCatalog(normalized);
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

  function downloadPlaylist() {
    if (!channels.length) {
      setError("尚无频道可导出。");
      return;
    }
    const url = URL.createObjectURL(new Blob([exportM3u(channels)], { type: "audio/x-mpegurl;charset=utf-8" }));
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = "tv-next-playlist.m3u";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 30_000);
    // Export includes source URLs and query-string tokens. Treat the file as private.
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
      <a className="skip-link" href="#main-content">跳转到主要内容</a>
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark">▶</span><div><strong>TV-Next</strong><small>Personal media workspace</small></div></div>
        <p className="side-heading">LIBRARY</p>
        <button className={tab === "playlist" && collection === "all" ? "nav active" : "nav"} aria-pressed={tab === "playlist" && collection === "all"} onClick={() => { setTab("playlist"); setCollection("all"); setError(""); }}>☷ <span>播放列表</span></button>
        <button className={tab === "playlist" && collection === "favorites" ? "nav active" : "nav"} aria-pressed={tab === "playlist" && collection === "favorites"} onClick={() => { setTab("playlist"); setCollection("favorites"); setError(""); }}>☆ <span>我的收藏</span> <small>{library.favorites.length}</small></button>
        <button className={tab === "playlist" && collection === "recent" ? "nav active" : "nav"} aria-pressed={tab === "playlist" && collection === "recent"} onClick={() => { setTab("playlist"); setCollection("recent"); setError(""); }}>◷ <span>最近播放</span></button>
        <p className="side-heading">TOOLS</p>
        <button className={tab === "config" ? "nav active" : "nav"} aria-pressed={tab === "config"} onClick={() => { setTab("config"); setError(""); }}>⚙ <span>配置检查</span></button>
        <button className={tab === "media" ? "nav active" : "nav"} aria-pressed={tab === "media"} onClick={() => { setTab("media"); setError(""); }}>▣ <span>影视目录</span></button>
        <button className={tab === "epg" ? "nav active" : "nav"} aria-pressed={tab === "epg"} onClick={() => { setTab("epg"); setError(""); }}>▤ <span>直播节目表</span></button>
        <button className={tab === "home" ? "nav active" : "nav"} aria-pressed={tab === "home"} onClick={() => setTab("home")}>⌂ <span>家庭服务器</span></button>
        <div className="side-bottom"><p>Phase 1 · Local library</p><small>资料仅保存在此浏览器。不会自动同步到服务器。</small></div>
      </aside>
      <main id="main-content" tabIndex={-1}>
        <header><div><p className="eyebrow">TV-NEXT / PLAYER</p><h1>你的媒体，随处播放。</h1><p className="subtitle">M3U 频道 · 收藏 · 最近播放 · 点播断点续播</p></div><span className="tag">P1 PREVIEW</span></header>
        {error && <div className="alert" role="alert">{error}</div>}
        {storageWarning && <div className="alert" role="status">{storageWarning}</div>}
        <section className="player-card">
          <div className="player-header"><span className="small-dot" /> {localVideo?.name || selected?.name || "尚未选择媒体"} <span className="player-type">{localVideo ? "LOCAL / NOT SAVED" : "HTTP(S) · HLS / MP4"}</span></div>
          <div className="video-stage">
          <video ref={videoRef} controls playsInline preload="metadata" aria-label="视频播放器">
            {subtitleUrl && <track key={subtitleUrl} kind="subtitles" label="外置字幕" srcLang="zh" src={subtitleUrl} default />}
          </video>
          <DanmakuOverlay video={videoRef} comments={danmaku} settings={danmakuSettings}/>
          </div>
          {playerError && <p className="player-error" role="alert">{playerError}</p>}
          {(selected || localVideo) && <div className="player-actions">
            <button className="secondary" onClick={() => void enterFullscreen()}>⛶ 全屏</button>
            <button className="secondary" onClick={() => void enterPictureInPicture()}>▣ 画中画</button>
            <label className="file-picker">加载 SRT / VTT / ASS / SSA
              <input type="file" accept=".srt,.vtt,.ass,.ssa,text/vtt,application/x-subrip" onChange={(e) => { void importSubtitle(e.target.files?.[0]); e.target.value = ""; }} />
            </label>
            {selected?.subtitles?.map((source,i)=><button key={i} onClick={()=>void loadSubtitleSource(source.url,source.name)}>{source.name}</button>)}
            {subtitleUrl && <label>字幕偏移（正值延后） <input aria-label="字幕偏移" type="range" min="-10" max="10" step="0.5" value={subtitleOffset} onChange={(e) => setSubtitleOffset(Number(e.target.value))} /> {subtitleOffset.toFixed(1)} 秒</label>}
            {subtitleUrl && <button className="secondary" onClick={() => { setSubtitleOriginal(""); setSubtitleUrl(null); setSubtitleName(""); setSubtitleOffset(0); }} title={subtitleName}>移除字幕</button>}
          </div>}
          {(selected || localVideo) && <details className="danmaku-controls"><summary>弹幕 · {danmaku.length} 条</summary>
            <label className="file-picker">导入弹幕 XML / JSON<input type="file" accept=".xml,.json" onChange={e=>{const f=e.target.files?.[0]; if(f)void loadDanmakuFile(f);e.target.value="";}}/></label>
            {selected?.danmaku?.map((source,i)=><button key={i} onClick={()=>void loadDanmakuSource(source.url)}>{source.name}</button>)}
            <label><input type="checkbox" checked={danmakuSettings.enabled} onChange={e=>setDanmakuSettings(s=>({...s,enabled:e.target.checked}))}/>显示弹幕</label>
            <label>透明度<input type="range" min="0.1" max="1" step="0.1" value={danmakuSettings.opacity} onChange={e=>setDanmakuSettings(s=>({...s,opacity:Number(e.target.value)}))}/></label>
            <label>字号<input type="range" min="12" max="40" value={danmakuSettings.fontSize} onChange={e=>setDanmakuSettings(s=>({...s,fontSize:Number(e.target.value)}))}/></label>
            <label>显示区域<select value={danmakuSettings.area} onChange={e=>setDanmakuSettings(s=>({...s,area:Number(e.target.value)}))}><option value="0.25">1/4 屏</option><option value="0.5">半屏</option><option value="1">全屏</option></select></label>
            <label>弹幕时长<input type="range" min="4" max="15" value={danmakuSettings.duration} onChange={e=>setDanmakuSettings(s=>({...s,duration:Number(e.target.value)}))}/></label>
            <label>偏移（秒）<input type="number" min="-120" max="120" value={danmakuSettings.offset} onChange={e=>setDanmakuSettings(s=>({...s,offset:Math.max(-120,Math.min(120,Number(e.target.value)||0))}))}/></label>
            <label>屏蔽词（逗号分隔）<input maxLength={1000} value={danmakuSettings.blocked} onChange={e=>setDanmakuSettings(s=>({...s,blocked:e.target.value}))}/></label>
            <button onClick={()=>setDanmaku([])}>清空弹幕</button>
          </details>}
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
        <div className="quick-play"><label htmlFor="manual-url">快速播放</label><div className="inline-controls"><input id="manual-url" type="url" placeholder="https://example.org/video.m3u8" value={manualUrl} onChange={(e) => setManualUrl(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") openManual(); }}/><button className="primary" onClick={openManual}>播放 URL →</button></div>
          <div className="local-file-actions">
            <label className="file-picker">从本机播放视频 / 音频
              <input type="file" accept="video/mp4,video/quicktime,video/webm,video/ogg,audio/*,.m4v,.mov,.mp4,.webm,.ogv,.ogg" onChange={(e) => { playLocalFile(e.target.files?.[0]); e.target.value = ""; }}/>
            </label>
            <span className="hint">本地文件不会上传，也不会保存到播放历史；能否播放取决于浏览器编解码能力。</span>
          </div>
        </div>
        {tab === "home" ? <HomeServerPanel library={library} onRestore={setLibrary} session={homeSession} onSessionChange={setHomeSession} remoteState={remoteState}/> : tab === "media" ? <><SubscriptionBrowser session={homeSession} onPlay={playChannel} onImport={channels=>setLibrary(state=>({...state,channels:channels.slice(0,1500)}))}/><CloudBrowser onPlay={playChannel}/><MediaBrowser onPlay={playChannel} /></> : tab === "epg" ? <EpgGuide channels={channels} onPlay={playChannel} session={homeSession} /> : tab === "config" ? <>
          <div className="section-heading"><h2>检查 FongMi JSON 配置</h2><span>STATIC INSPECTION ONLY</span></div>
          <section className="panel">
            <p className="hint">只展示站点、直播分组及 Spider 声明，不会运行 Java/JS/Python 插件或获取远程内容。</p>
            <textarea aria-label="JSON 配置内容" rows={7} spellCheck={false} value={configText} onChange={(event) => setConfigText(event.target.value)} placeholder={'{"sites":[],"lives":[]}'}/>
            <div className="panel-actions"><label className="file-picker">选择 JSON 文件<input type="file" accept=".json,application/json,text/plain" onChange={(event) => { void importFile(event.target.files?.[0]); event.target.value = ""; }}/></label><button disabled={busy} className="primary" onClick={() => void inspectConfig()}>{busy ? "检查中…" : "检查配置"}</button></div>
          </section>
          {preview && <section className="results"><div className="section-heading"><h2>配置概况</h2><span>NO CODE EXECUTION</span></div><div className="stats"><div><strong>{preview.sites.length}</strong><small>站点预览（最多 1000）</small></div><div><strong>{preview.liveGroupCount}</strong><small>直播分组</small></div><div><strong>{preview.spiderDeclared ? "Yes" : "No"}</strong><small>声明 Spider</small></div></div><div className="channel-list">{preview.sites.map((site, i) => <div className="channel" key={site.key + i}><span className="channel-avatar">◈</span><span className="channel-name"><strong>{site.name || site.key || "Unnamed"}</strong><small>type {site.type ?? "unknown"} · {site.key}</small></span></div>)}</div></section>}
          {catalog && <section className="results">
            <div className="section-heading"><h2>FongMi 站点目录</h2><span>{catalog.sites.length} SITES · PREVIEW ONLY</span></div>
            <p className="hint">这些站点尚未连接 Spider，不能搜索、展示影视内容或执行脚本。隐藏站点以灰色标记。</p>
            <div className="channel-list">{catalog.sites.map((site) =>
              <div className="channel" key={site.key}>
                <span className="channel-avatar">◈</span>
                <span className="channel-name">
                  <strong>{site.name}</strong>
                  <small>{site.key} · type {site.type ?? "unknown"} · {site.searchable ? "支持搜索（原配置声明）" : "原配置禁止搜索"}
                    {site.hidden ? " · 已隐藏" : ""}</small>
                  {site.categories.length > 0 && <small>分类：{site.categories.join(" / ")}</small>}
                </span>
              </div>
            )}</div>
            <div className="section-heading"><h2>直播目录</h2><span>{catalog.directPlayableChannelCount} DIRECT URLS</span></div>
            <p className="hint">仅纯 HTTP(S) 播放地址提供播放按钮；含特殊路由语法、额外请求头或 Spider 依赖的线路仍不能播放。</p>
            {catalog.liveSources.map((source, index) =>
              <div key={source.name + index} className="catalog-source">
                <h3>{source.name}</h3>
                {source.groups.map((group, groupIndex) =>
                  <div key={group.name + groupIndex}>
                    <p className="catalog-group-title">{group.name} · {group.channels.length} 个频道</p>
                    <div className="channel-list">
                      {group.channels.map((channel, channelIndex) =>
                        <div className="channel-line" key={channel.name + channelIndex}>
                          <div className="channel catalog-channel">
                            <span className="channel-name"><strong>{channel.name}</strong>
                              <small>{channel.sourceCount} 条配置线路</small>
                            </span>
                          </div>
                          {channel.directUrl
                            ? <button className="secondary" onClick={() => playChannel({
                                name: channel.name,
                                url: channel.directUrl!,
                                group: group.name
                              })}>播放</button>
                            : <span className="catalog-unavailable">需适配</span>}
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </div>
            )}
            {catalog.warnings.map((warning, i) => <p className="hint" key={i}>{warning}</p>)}
          </section>}
        </> : <>
          <div className="section-heading"><h2>导入 M3U 播放列表</h2><span>{channels.length} CHANNELS</span></div>
          <section className="panel">
            <p className="hint">导入 .m3u 或文本；新列表会替换当前频道，但不会清空收藏和历史。最多保存 1500 个频道。</p>
            <textarea aria-label="M3U 内容" spellCheck={false} rows={5} value={rawText} onChange={(event) => setRawText(event.target.value)} placeholder={'#EXTM3U\n#EXTINF:-1 group-title="Demo",My Channel\nhttps://example.org/stream.m3u8'}/>
            <div className="panel-actions"><label className="file-picker">选择 M3U 文件<input type="file" accept=".m3u,.txt,text/plain" onChange={(event) => { void importFile(event.target.files?.[0]); event.target.value = ""; }}/></label><div className="inline-controls"><button className="secondary" disabled={!channels.length} onClick={downloadPlaylist}>导出 M3U</button><button disabled={busy} className="primary" onClick={() => void importPlaylist()}>{busy ? "解析中…" : "导入频道"}</button></div></div>
          </section>
          <section className="results">
            <div className="section-heading"><h2>{collection === "favorites" ? "我的收藏" : collection === "recent" ? "最近播放" : "频道列表"}</h2><span>{collection === "all" ? groups.length + " GROUPS" : displayed.length + " ITEMS"}</span></div>
            <div className="library-toolbar"><input className="filter-input" aria-label="搜索频道" placeholder="按名称或分组搜索…" value={filter} onChange={(event) => setFilter(event.target.value)}/><button className="secondary danger" onClick={resetLibrary}>清空本地媒体库</button></div>
            {displayed.length === 0 && <p className="hint">{collection === "favorites" ? "还没有收藏的频道。" : collection === "recent" ? "还没有播放记录。" : "频道列表为空，请导入 M3U。"}</p>}
            <div className="channel-list">{displayed.map((channel, index) => <div className="channel-line" key={channel.url + index}>
              <button className={selected?.url === channel.url ? "channel selected" : "channel"} aria-pressed={selected?.url === channel.url} onClick={() => playChannel(channel)}>
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
