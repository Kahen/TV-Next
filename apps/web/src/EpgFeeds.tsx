import { useEffect, useRef, useState } from "react";
import { homeRequest } from "./homeApi";
import type { HomeSession } from "./homeApi";
import type { Channel } from "./api";
import type { EpgGuideResponse } from "./epg";
import { epgChannelsFromPlaylist } from "./epg";
export interface EpgFeed { id:string;name:string;url:string;intervalMinutes:number;enabled:boolean;updatedAt:number;nextRefresh:number;lastError:string|null;available:boolean }

export default function EpgFeeds({session,channels,hours,onGuide,resetKey=0,onRequest}:{resetKey?:number;onRequest?:()=>void;session:HomeSession|null;channels:Channel[];hours:number;onGuide:(guide:EpgGuideResponse,channels:Channel[])=>void}) {
  const [feeds,setFeeds]=useState<EpgFeed[]>([]);
  const [name,setName]=useState("");const [url,setUrl]=useState("");const [interval,setInterval]=useState(360);
  const [error,setError]=useState("");const [busy,setBusy]=useState(false);
  const generation=useRef(0);
  const sessionKey=session?.token;
  useEffect(()=>{generation.current++;setFeeds([]);setError("");setBusy(false);setName("");setUrl("");return ()=>{generation.current++;};},[sessionKey]);
  // Channel changes invalidate in-flight guide results, including same-length reorder/replacement.
  useEffect(()=>{generation.current++;setBusy(false);},[channels,hours,resetKey]);
  async function run(action:(token:string)=>Promise<void>){
    if(!sessionKey)return;const id=++generation.current;setBusy(true);setError("");
    try{await action(sessionKey);}catch(e){if(id===generation.current)setError(e instanceof Error?e.message:"节目表请求失败");}
    finally{if(id===generation.current)setBusy(false);}
  }
  async function reload(token:string,id:number){const value=await homeRequest<EpgFeed[]>("epg/feeds",undefined,token);if(id===generation.current)setFeeds(value);}
  const list=()=>run(async token=>reload(token,generation.current));
  const create=()=>run(async token=>{const id=generation.current;await homeRequest<EpgFeed>("epg/feeds",{name,url,intervalMinutes:interval,enabled:true},token);if(id===generation.current){setName("");setUrl("");await reload(token,id);}});
  const mutate=(feed:EpgFeed,action:"remove"|"refresh")=>run(async token=>{const id=generation.current;await homeRequest("epg/feeds/"+feed.id+"/"+action,{},token);await reload(token,id);});
  const guide=(feed:EpgFeed)=>{onRequest?.();return run(async token=>{const id=generation.current;const snapshot=channels.slice(0,300);const value=await homeRequest<EpgGuideResponse>("epg/feeds/"+feed.id+"/guide",{channels:epgChannelsFromPlaylist(snapshot),hours,pastHours:168},token);if(id===generation.current)onGuide(value,snapshot);});};
  if(!session)return <p className="hint">登录家庭服务器账号后可保存 XMLTV / XMLTV.gz 订阅，并由服务器定时更新。</p>;
  return <fieldset><legend>节目表订阅 · {session.user.username}</legend>
    <p className="hint">最多 10 个订阅，每份下载及解压后最多 1 MiB。服务器按周期刷新；失败时保留上次数据。</p>
    <label>节目表名称<input value={name} onChange={e=>setName(e.target.value)} maxLength={80}/></label>
    <label>XMLTV 订阅网址<input type="url" value={url} onChange={e=>setUrl(e.target.value)} maxLength={2048}/></label>
    <label>刷新间隔<select value={interval} onChange={e=>setInterval(Number(e.target.value))}><option value={15}>15 分钟</option><option value={60}>1 小时</option><option value={360}>6 小时</option><option value={1440}>24 小时</option></select></label>
    <button disabled={busy||!name.trim()||!url.trim()} onClick={()=>void create()}>保存订阅</button>
    <button disabled={busy} onClick={()=>void list()}>读取订阅</button>
    {error&&<p role="alert">{error}</p>}
    {feeds.map(feed=><div key={feed.id}><strong>{feed.name}</strong><p className="hint">{feed.updatedAt?"已缓存 · "+new Date(feed.updatedAt).toLocaleString():"尚未下载"} · {feed.enabled?"定时更新已开启":"定时更新已关闭"}</p>
      {feed.lastError&&<p role="status">{feed.lastError}</p>}
      <button disabled={busy} onClick={()=>void mutate(feed,"refresh")}>立即刷新</button>
      <button disabled={busy||!feed.available||!channels.length} onClick={()=>void guide(feed)}>显示节目表</button>
      <button disabled={busy} onClick={()=>void mutate(feed,"remove")}>删除订阅</button>
    </div>)}
  </fieldset>;
}
