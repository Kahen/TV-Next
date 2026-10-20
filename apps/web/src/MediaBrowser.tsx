import { useState } from "react";
import { postMedia } from "./api";
import type { Channel, MediaDetail, MediaItem, MediaPage, MediaPlayback } from "./api";
import { validMediaUrl } from "./library";

type ViewMode = "home" | "category" | "search";
export default function MediaBrowser({ onPlay }: { onPlay: (media: Channel) => void }) {
  const [content, setContent] = useState("");
  const [page, setPage] = useState<MediaPage | null>(null);
  const [detail, setDetail] = useState<MediaDetail | null>(null);
  const [mode, setMode] = useState<ViewMode>("home");
  const [categoryId, setCategoryId] = useState("");
  const [searchText, setSearchText] = useState("");
  const [activeSearch, setActiveSearch] = useState("");
  const [lineIndex, setLineIndex] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function browse(nextMode: ViewMode, nextPage = 1, category = categoryId, search = activeSearch) {
    setBusy(true); setError(""); setDetail(null);
    try {
      const result = await postMedia<MediaPage>("/api/v1/media/" + nextMode, {
        content, page: nextPage, pageSize: 40,
        ...(nextMode === "category" ? { categoryId: category } : {}),
        ...(nextMode === "search" ? { query: search } : {})
      });
      setPage(result); setMode(nextMode); setCategoryId(category); setActiveSearch(search);
    } catch (e) { setError(e instanceof Error ? e.message : "请求失败"); }
    finally { setBusy(false); }
  }

  async function inspect(item: MediaItem) {
    setBusy(true); setError("");
    try {
      setDetail(await postMedia<MediaDetail>("/api/v1/media/detail", { content, vodId: item.id }));
      setLineIndex(0);
    } catch (e) { setError(e instanceof Error ? e.message : "无法加载详情"); }
    finally { setBusy(false); }
  }

  async function selectEpisode(vodId: string, episodeIndex: number) {
    setBusy(true); setError("");
    try {
      const result = await postMedia<MediaPlayback>("/api/v1/media/play", {
        content, vodId, lineIndex, episodeIndex
      });
      if (!validMediaUrl(result.url)) throw new Error("播放 URL 无效");
      onPlay({
        name: (detail?.item.name || "媒体") + " · " + result.name,
        url: result.url,
        group: result.lineName
      });
    } catch (e) { setError(e instanceof Error ? e.message : "播放地址不可用"); }
    finally { setBusy(false); }
  }

  async function loadFile(file: File | undefined) {
    if (!file) return;
    if (file.size > 1_048_576) { setError("最多支持 1 MiB 的 JSON"); return; }
    try { setContent(await file.text()); setPage(null); setDetail(null); setError(""); }
    catch { setError("无法读取文件"); }
  }

  return <section className="results media-browser">
    <div className="section-heading"><h2>影视目录 · FongMi Result</h2><span>STATIC PROVIDER</span></div>
    <p className="hint">粘贴由你提供的 class/list JSON 结果，仅在后端解析这些数据，不会联网访问第三方站点或运行 Spider。示例内容中的 example.org 不是可播放视频源。</p>
    <textarea rows={6} spellCheck={false} aria-label="FongMi Result JSON"
      placeholder='{"class":[{"type_id":"movie","type_name":"电影"}],"list":[{"vod_id":"1","vod_name":"演示影片","type_id":"movie"}]}'
      value={content}
      onChange={(e) => { setContent(e.target.value); setPage(null); setDetail(null); }}/>
    <div className="panel-actions">
      <label className="file-picker">导入 JSON 文件<input type="file" accept=".json,application/json"
        onChange={(e) => { void loadFile(e.target.files?.[0]); e.target.value = ""; }}/></label>
      <button className="primary" disabled={busy} onClick={() => void browse("home", 1)}>浏览首页</button>
    </div>
    {error && <p className="alert" role="alert">{error}</p>}
    {page && <>
      <div className="media-controls">
        <button className={mode === "home" ? "secondary media-selected" : "secondary"}
          disabled={busy} onClick={() => void browse("home", 1)}>全部</button>
        {page.categories.map((category) =>
          <button key={category.id} className={mode === "category" && categoryId === category.id ? "secondary media-selected" : "secondary"}
            disabled={busy} onClick={() => void browse("category", 1, category.id)}>{category.name}</button>)}
      </div>
      <div className="inline-controls">
        <input className="filter-input" type="search" aria-label="搜索当前影视目录"
          value={searchText} placeholder="按片名搜索 JSON 结果…"
          onChange={(e) => setSearchText(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") void browse("search", 1, categoryId, searchText); }}/>
        <button className="secondary" disabled={busy || !searchText.trim()}
          onClick={() => void browse("search", 1, categoryId, searchText)}>搜索</button>
      </div>
      <p className="hint">共 {page.total} 项 · 第 {page.page} 页，数据来源为导入的 Result JSON。</p>
      <div className="media-grid">
        {page.items.map((item) => <button key={item.id} className="media-tile"
          disabled={busy} onClick={() => void inspect(item)}>
          <span className="media-tile-icon">▶</span>
          <strong>{item.name}</strong>
          <small>{item.categoryName || item.categoryId || "其他"} · {item.year || "未知年份"}</small>
          {item.remarks && <small>{item.remarks}</small>}
        </button>)}
      </div>
      <div className="media-pagination">
        <button className="secondary" disabled={busy || page.page <= 1}
          onClick={() => void browse(mode, page.page - 1)}>上一页</button>
        <button className="secondary" disabled={busy || !page.hasMore}
          onClick={() => void browse(mode, page.page + 1)}>下一页</button>
      </div>
    </>}
    {detail && <div className="media-detail">
      <div className="section-heading"><h2>{detail.item.name}</h2><span>{detail.provider}</span></div>
      {detail.description && <p>{detail.description}</p>}
      {detail.director && <p className="hint">导演：{detail.director}</p>}
      {detail.actors && <p className="hint">演员：{detail.actors}</p>}
      {detail.lines.length === 0 && <p className="hint">该结果尚无可解析的播放线路。</p>}
      <div className="media-controls">
        {detail.lines.map((line, i) => <button key={i}
          className={lineIndex === i ? "secondary media-selected" : "secondary"}
          onClick={() => setLineIndex(i)}>{line.name}</button>)}
      </div>
      {detail.lines[lineIndex] && <div className="media-episodes">
        {detail.lines[lineIndex].episodes.map((episode, i) =>
          <button key={i} className="secondary" disabled={busy || !episode.playable}
            title={episode.playable ? "尝试播放" : "需要 Spider 或其他解析器"}
            onClick={() => void selectEpisode(detail.item.id, i)}>
            {episode.name}{episode.playable ? "" : " · 需适配"}
          </button>)}
      </div>}
    </div>}
  </section>;
}
