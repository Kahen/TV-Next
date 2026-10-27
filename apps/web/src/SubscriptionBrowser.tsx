import { useEffect, useRef, useState } from "react";
import { requestJson } from "./api";
import type { Channel, MediaDetail, MediaItem, MediaPage, MediaPlayback, SubscriptionDocument } from "./api";
import { initialSiteFilters } from "./subscriptionFilters";
import { searchAcrossSites } from "./crossSiteSearch";
import { interpretSubscriptionAction } from "./subscriptionAction";
import type { SubscriptionActionResult } from "./subscriptionAction";
import type { SiteFilterMap } from "./subscriptionFilters";
import type { HomeSession } from "./homeApi";
export default function SubscriptionBrowser({onPlay, onImport,session}: {session?:HomeSession|null;onPlay: (channel: Channel) => void; onImport?: (channels: Channel[]) => void}) {
  const [url, setUrl] = useState("");
  const [text, setText] = useState("");
  const [doc, setDoc] = useState<SubscriptionDocument | null>(null);
  const [siteKey, setSite] = useState("");
  const [page, setPage] = useState<MediaPage | null>(null);
  const [category, setCategory] = useState("");
  const [filterCatalog,setFilterCatalog]=useState<SiteFilterMap>({});
  const [filters,setFilters]=useState<Record<string,string>>({});
  const [appliedFilters,setAppliedFilters]=useState<Record<string,string>>({});
  const [query, setQuery] = useState("");
  const [mode, setMode] = useState("home");
  const [detail, setDetail] = useState<MediaDetail | null>(null);
  const [line, setLine] = useState(0);
  const [actionResult, setActionResult] = useState<SubscriptionActionResult | null>(null);
  const [found, setFound] = useState<import("./crossSiteSearch").CrossSiteHit[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const active = useRef<AbortController | null>(null);
  const requestId = useRef(0);
  useEffect(() => () => active.current?.abort(), []);
  useEffect(()=>{active.current?.abort();requestId.current++;setBusy(false);setActionResult(null);},[session?.token]);
  function start() { active.current?.abort(); const controller = new AbortController(); active.current = controller; const id = ++requestId.current; setBusy(true); setError(""); setActionResult(null); return { controller, id }; }
  const sourceRequest=<T,>(path:string,data:unknown,signal?:AbortSignal)=>requestJson<T>(path,data,signal,session?.token);
  const body = (key = siteKey) => ({content: doc?.content, url: doc?.url, siteKey: key});
  async function load(content = text, address = url) {
    const {controller, id} = start();
    try {
      const result = await sourceRequest<SubscriptionDocument>("/api/v1/subscriptions/load", { content, url: address }, controller.signal);
      if (id !== requestId.current) return;
      setActionResult(null); setDoc(result); setPage(null); setDetail(null); setFound([]); setSite("");setFilterCatalog({});setFilters({});setAppliedFilters({});setCategory("");
    } catch (e) { if (id === requestId.current && !controller.signal.aborted) setError(e instanceof Error ? e.message : "订阅加载失败"); }
    finally { if (id === requestId.current) setBusy(false); }
  }
  async function browse(key: string, op = "home", nextPage = 1, type = category, selectedFilters?:Record<string,string>, bypassCache=false) {
    const same=key===siteKey;
    const choices=op!=="category"?{}:selectedFilters??(same&&type===category&&mode==="category"?appliedFilters:initialSiteFilters((same?filterCatalog:{})[type]||[]));
    const {controller, id} = start();
    setActionResult(null); setDetail(null); setFound([]);
    try {
      const result = await sourceRequest<MediaPage>("/api/v1/subscriptions/" + op, {...body(key), page: nextPage, categoryId: type, query,filters:choices,bypassCache}, controller.signal);
      if (id !== requestId.current) return;
      setPage(result); setSite(key); setMode(op); setCategory(op==="home"?"":type);
      setFilterCatalog(same?{...filterCatalog,...result.filters}:result.filters||{});
      setAppliedFilters(op==="category"?choices:{});
      // Paging must never submit unsaved dropdown edits. Keep drafts for explicit Apply/Reset.
      if (op!=="category" || nextPage===1 || !same || type!==category || mode!=="category") setFilters(op==="category"?choices:{});
    } catch (e) { if (id === requestId.current && !controller.signal.aborted) setError(e instanceof Error ? e.message : "站点请求失败"); }
    finally { if (id === requestId.current) setBusy(false); }
  }
  async function inspect(item: MediaItem, key = siteKey) {
    if (item.folder) { await browse(key,"category",1,item.id); return; }
    const {controller, id} = start();
    try {
      if (item.action) {
        const result = await sourceRequest<unknown>("/api/v1/subscriptions/action",{...body(key),action:item.action},controller.signal);
        if (id === requestId.current && !controller.signal.aborted) setActionResult(interpretSubscriptionAction(result));
        return;
      }
      const result = await sourceRequest<MediaDetail>("/api/v1/subscriptions/detail", {...body(key), vodId: item.id}, controller.signal);
      if (id === requestId.current) { setDetail(result); setLine(0); setSite(key); }
    } catch (e) { if (id === requestId.current && !controller.signal.aborted) setError(e instanceof Error ? e.message : "详情加载失败"); }
    finally { if (id === requestId.current) setBusy(false); }
  }
  async function play(index: number) {
    if (!detail) return;
    const {controller, id} = start();
    try {
      const p = await sourceRequest<MediaPlayback>("/api/v1/subscriptions/play", {...body(), vodId: detail.item.id, lineIndex: line, episodeIndex: index}, controller.signal);
      if (id === requestId.current) onPlay({name: detail.item.name + " · " + p.name, url: p.url, group: p.lineName, headers: p.headers, subtitles: p.subtitles, danmaku: p.danmaku});
    } catch (e) { if (id === requestId.current && !controller.signal.aborted) setError(e instanceof Error ? e.message : "播放解析失败"); }
    finally { if (id === requestId.current) setBusy(false); }
  }
  async function loadLive(index: number) {
    const {controller,id}=start();
    try { const result=await sourceRequest<{channels:Channel[];warnings:string[]}>("/api/v1/subscriptions/live",{content:doc?.content,url:doc?.url,liveIndex:index},controller.signal);
      if(id===requestId.current){onImport?.(result.channels);if(result.warnings.length)setError(result.warnings.join(" · "));}
    }catch(e){if(id===requestId.current&&!controller.signal.aborted)setError(e instanceof Error?e.message:"直播加载失败");}
    finally{if(id===requestId.current)setBusy(false);}
  }
  async function searchAll() {
    if (!doc || !query.trim()) return;
    const { controller, id } = start();
    setFound([]); setDetail(null); setPage(null);
    try {
      const result = await searchAcrossSites(doc.sites,
        (site, page, signal) => sourceRequest<MediaPage>("/api/v1/subscriptions/search",
          { ...body(site.key), query: query.trim(), page, pageSize: 40 }, signal),
        controller.signal);
      if (id !== requestId.current) return;
      setFound(result.items);
      const messages = [
        ...(result.failed.length ? ["以下站点未返回结果：" + result.failed.join("、")] : []),
        ...result.warnings
      ];
      if (messages.length) setError(messages.join(" · "));
    } catch (e) {
      if (id === requestId.current && !controller.signal.aborted)
        setError(e instanceof Error ? e.message : "跨站搜索失败");
    } finally {
      if (id === requestId.current) setBusy(false);
    }
  }
  return <section className="results media-browser">
    <div className="section-heading"><h2>TVBox / FongMi 订阅</h2><span>原版协议</span></div>
    <label>订阅地址（也可作为粘贴内容的相对路径基准）<input className="filter-input" type="url" value={url} onChange={e=>setUrl(e.target.value)} placeholder="https://your-server/config.json"/></label>
    <textarea aria-label="订阅配置" rows={4} value={text} onChange={e=>setText(e.target.value)} placeholder="粘贴原版配置，或留空后加载订阅地址"/>
    <div className="panel-actions"><button className="primary" disabled={busy} onClick={()=>void load()}>加载订阅</button>
      <label className="file-picker">导入配置文件<input type="file" accept=".json,.txt" onChange={e=>{const file=e.target.files?.[0]; if(file) {if(file.size>1048576)setError("配置最多 1 MiB");else void file.text().then(value=>{setText(value);void load(value);});} e.target.value="";}}/></label>
      {busy && <button className="secondary" onClick={()=>{active.current?.abort();requestId.current++;setBusy(false);setActionResult(null);}}>取消请求</button>}</div>
    {actionResult && <div className="action-result" role="status">
      {actionResult.message && <p>{actionResult.message}</p>}
      {actionResult.web && <p><a href={actionResult.web.url} target="_blank" rel="noopener noreferrer">在外部浏览器打开站点网页</a></p>}
      {actionResult.web?.hasUnsupportedBrowserFeatures && <p className="hint">原版内嵌视图或 Cookie 自动关闭尚未支持；仅手动打开外部浏览器，不同步凭据。</p>}
      {actionResult.unsupported && <p className="hint">站点返回了未支持的操作指令或不安全的网址，未执行。</p>}
    </div>}
    {error && <p role="alert" className="alert">{error}</p>}
    {doc && <>
      {Array.from({length:Math.min(doc.liveCount,50)},(_,i)=><button key={i} disabled={busy} onClick={()=>void loadLive(i)}>导入直播源 {i+1}</button>)}
      {doc.warnings.map((w,i)=><p className="hint" key={i}>{w}</p>)}
      {doc.depots.length>0 && <div className="media-controls">{doc.depots.map(d=><button key={d.url} disabled={busy} onClick={()=>{setUrl(d.url);setText("");void load("",d.url);}}>{d.name}</button>)}</div>}
      <div className="media-controls">{doc.sites.filter(s=>!s.hidden).map(s=><button className={siteKey===s.key?"secondary media-selected":"secondary"} key={s.key} disabled={busy||![0,1,2,4].includes(s.type)} title={s.support} onClick={()=>void browse(s.key)}>{s.name}{s.type===3?" · 需 Spider 适配":""}</button>)}</div>
      <div className="inline-controls"><input className="filter-input" aria-label="搜索订阅站点" value={query} onChange={e=>setQuery(e.target.value)}/><button disabled={busy||!query.trim()||!siteKey} onClick={()=>void browse(siteKey,"search")}>当前站点搜索</button><button disabled={busy||!query.trim()} onClick={()=>void searchAll()}>跨站搜索</button></div>
    </>}
    {page && <>
      <div className="media-controls">{page.categories.map(c=><button key={c.id} disabled={busy} onClick={()=>void browse(siteKey,"category",1,c.id)}>{c.name}</button>)}</div>
      {mode==="category"&&(filterCatalog[category]||[]).length>0&&<div className="media-controls">
        {(filterCatalog[category]||[]).map(filter=><label key={filter.key}>{filter.name||filter.key}<select aria-label={"筛选："+(filter.name||filter.key)} disabled={busy} value={filters[filter.key]??filter.init??""} onChange={e=>setFilters(value=>({...value,[filter.key]:e.target.value}))}>
          {!filter.value.some(v=>v.v===(filters[filter.key]??filter.init??""))&&<option value={filters[filter.key]??filter.init??""}>默认</option>}
          {filter.value.map(value=><option key={value.v} value={value.v}>{value.n||value.v||"全部"}</option>)}
        </select></label>)}
        {(filterCatalog[category]||[]).some(f=>(filters[f.key]??f.init??"")!==(appliedFilters[f.key]??f.init??""))&&<span role="status">筛选尚未应用，翻页仍使用已应用条件</span>}
        <button disabled={busy} onClick={()=>void browse(siteKey,"category",1,category,{...initialSiteFilters(filterCatalog[category]||[]),...filters})}>应用筛选</button>
        <button disabled={busy} onClick={()=>void browse(siteKey,"category",1,category,initialSiteFilters(filterCatalog[category]||[]))}>重置筛选</button>
      </div>}
      <div className="media-grid">{page.items.map(item=><button key={item.id} disabled={busy} className="media-tile" onClick={()=>void inspect(item)}><strong>{item.folder?"📁 ":""}{item.name}</strong><small>{item.remarks}</small></button>)}</div>
      {mode==="search"&&session&&<button disabled={busy} onClick={()=>void browse(siteKey,"search",page.page,category,undefined,true)}>刷新搜索结果</button>}
      <div className="media-pagination"><button disabled={busy||page.page<=1} onClick={()=>void browse(siteKey,mode,page.page-1)}>上一页</button><span>第 {page.page} 页</span><button disabled={busy||!page.hasMore} onClick={()=>void browse(siteKey,mode,page.page+1)}>下一页</button></div>
    </>}
    {found.length>0 && <div className="media-grid">{found.map(x=><button key={x.siteKey+":"+x.item.id} disabled={busy} onClick={()=>void inspect(x.item,x.siteKey)}><strong>{x.item.name}</strong><small>{doc?.sites.find(s=>s.key===x.siteKey)?.name}</small></button>)}</div>}
    {detail && <div className="media-detail"><h3>{detail.item.name}</h3><p>{detail.description}</p>
      <div className="media-controls">{detail.lines.map((l,i)=><button key={i} onClick={()=>setLine(i)} aria-pressed={line===i}>{l.name}</button>)}</div>
      <div className="media-episodes">{detail.lines[line]?.episodes.map((e,i)=><button key={i} disabled={busy||!e.playable} onClick={()=>void play(i)}>{e.name}</button>)}</div>
    </div>}
  </section>;
}
