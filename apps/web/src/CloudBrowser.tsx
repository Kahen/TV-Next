import { useEffect, useRef, useState } from "react";
import { requestJson } from "./api";
import type { Channel } from "./api";
interface CloudPage {path:string;entries:{name:string;directory:boolean;size:number}[];page:number;hasMore:boolean}
export default function CloudBrowser({onPlay}:{onPlay:(c:Channel)=>void}) {
  const [server,setServer]=useState(""),[token,setToken]=useState(""),[password,setPassword]=useState("");
  const [page,setPage]=useState<CloudPage|null>(null),[error,setError]=useState(""),[busy,setBusy]=useState(false);
  const active=useRef<AbortController|null>(null);const revision=useRef(0);
  useEffect(()=>()=>active.current?.abort(),[]);
  async function run(path:string,number=1,play=false){
    active.current?.abort();const controller=new AbortController();active.current=controller;const id=++revision.current;setBusy(true);setError("");
    try{
      const body={server,token,password,path,page:number};
      if(play){const p=await requestJson<{url:string;name:string;headers:Record<string,string>}>("/api/v1/cloud/play",body,controller.signal);if(id===revision.current)onPlay({url:p.url,name:p.name,group:"网盘",headers:p.headers});}
      else {const result=await requestJson<CloudPage>("/api/v1/cloud/list",body,controller.signal);if(id===revision.current)setPage(result);}
    }catch(e){if(id===revision.current&&!controller.signal.aborted)setError(e instanceof Error?e.message:"网盘请求失败");}
    finally{if(id===revision.current)setBusy(false);}
  }
  const child=(name:string)=>(page?.path==="/"?"":page?.path||"")+"/"+name;
  return <section className="results"><h2>网盘 · AList / OpenList</h2><p className="hint">通过自己的网盘聚合服务浏览已挂载账号；令牌仅保留在本页内存。阿里云盘、夸克等原版订阅线路通过对应 HTTP Spider 解析。</p>
    <input className="filter-input" type="url" aria-label="网盘服务地址" value={server} onChange={e=>setServer(e.target.value)} placeholder="https://your-openlist.example/"/>
    <input type="password" autoComplete="off" aria-label="网盘访问令牌" value={token} onChange={e=>setToken(e.target.value)} placeholder="访问令牌（公开目录可留空）"/>
    <input type="password" autoComplete="off" aria-label="目录密码" value={password} onChange={e=>setPassword(e.target.value)} placeholder="目录密码（可选）"/>
    <button disabled={busy||!server} onClick={()=>void run("/")}>打开网盘</button>
    <button onClick={()=>{active.current?.abort();revision.current++;setBusy(false);setToken("");setPassword("");setPage(null);}}>断开并清除凭据</button>
    {error&&<p role="alert">{error}</p>}
    {page&&<><p>{page.path}</p><button disabled={busy||page.path==="/"} onClick={()=>void run(page.path.slice(0,page.path.lastIndexOf('/'))||"/")}>上级目录</button>
      <div className="channel-list">{page.entries.map(f=><button key={f.name} disabled={busy} className="channel" onClick={()=>void run(child(f.name),1,!f.directory)}>{f.directory?"📁":"▶"} {f.name}</button>)}</div>
      <button disabled={busy||page.page<=1} onClick={()=>void run(page.path,page.page-1)}>上一页</button><button disabled={busy||!page.hasMore} onClick={()=>void run(page.path,page.page+1)}>下一页</button></>}
  </section>;
}
