import { useEffect, useRef, useState } from "react";
import { homeRequest } from "./homeApi";
import type { Device,HomeSession,RemoteLibrary } from "./homeApi";
import { normalizeLibrary } from "./library";
import type { LibraryState } from "./library";
export default function HomeServerPanel({library,onRestore,session,onSessionChange,remoteState="未连接"}:{library:LibraryState;onRestore:(s:LibraryState)=>void;session:HomeSession|null;onSessionChange:(s:HomeSession|null)=>void;remoteState?:string}){
  const [username,setUsername]=useState(""),[password,setPassword]=useState(""),[name,setName]=useState("Web browser");
  const [devices,setDevices]=useState<Device[]>([]);
  const [remote,setRemote]=useState<RemoteLibrary|null>(null),[code,setCode]=useState(""),[claim,setClaim]=useState("");
  const [online,setOnline]=useState<{id:string;name:string;online:boolean}[]>([]),[target,setTarget]=useState(""),[seek,setSeek]=useState(0),[media,setMedia]=useState(""),[command,setCommand]=useState("");
  const [busy,setBusy]=useState(false),[error,setError]=useState(""),[notice,setNotice]=useState("");
  const epoch=useRef(0);useEffect(()=>()=>{epoch.current++},[]);
  async function run<T>(work:()=>Promise<T>,done:(v:T)=>void){const id=++epoch.current;setBusy(true);setError("");setNotice("");try{const result=await work();if(id===epoch.current)done(result);}catch(e){if(id===epoch.current)setError(e instanceof Error?e.message:"家庭服务器请求失败");}finally{if(id===epoch.current)setBusy(false);}}
  function connected(result:HomeSession){onSessionChange(result);setPassword("");setCode("");setClaim("");setRemote(null);setDevices([]);setNotice("设备已登录；同步由你主动发起。");}
  function auth(register=false){void run(()=>homeRequest<HomeSession>("auth/"+(register?"register":"login"),{username,password,deviceName:name}),connected);}
  function refresh(){if(session)void run(()=>homeRequest<RemoteLibrary>("library",undefined,session.token),data=>{setRemote(data);setNotice("已读取云端版本 "+data.revision+"；本地尚未替换。");});}
  function push(){if(!session||!remote)return;void run(()=>homeRequest<RemoteLibrary>("library",{expectedRevision:remote.revision,library:normalizeLibrary(library)},session.token),data=>{setRemote(data);setNotice("已保存云端版本 "+data.revision);});}
  function pull(){if(remote){onRestore(normalizeLibrary(remote.library));setNotice("本地媒体库已替换为云端版本 "+remote.revision);}}
  function logout(){epoch.current++;setBusy(false);onSessionChange(null);setDevices([]);setRemote(null);setCode("");setPassword("");}
  function download(){const url=URL.createObjectURL(new Blob([JSON.stringify(normalizeLibrary(library),null,2)],{type:"application/json"}));const a=document.createElement("a");a.href=url;a.download="tv-next-library.json";a.click();URL.revokeObjectURL(url);}
  return <section className="results"><h2>家庭服务器 · 账号与同步</h2>
    {!session?<><input aria-label="账号" autoComplete="username" value={username} onChange={e=>setUsername(e.target.value)} placeholder="账号"/><input aria-label="密码" type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="密码（注册至少 12 位）"/><input aria-label="设备名称" value={name} maxLength={80} onChange={e=>setName(e.target.value)}/><button disabled={busy} onClick={()=>auth()}>登录</button><button disabled={busy} onClick={()=>auth(true)}>注册账号</button>
      <div className="inline-controls"><input aria-label="配对码" value={claim} onChange={e=>setClaim(e.target.value)} placeholder="另一设备显示的配对码"/><button disabled={busy||!claim} onClick={()=>void run(()=>homeRequest<HomeSession>("pairings/claim",{code:claim,deviceName:name}),connected)}>通过配对码登录</button></div></>:<>
      <p>遥控接收端：{remoteState}</p>
      <p>{session.user.username} · {session.device.name}</p><button onClick={logout}>退出本页</button>
      <div className="panel-actions"><button disabled={busy} onClick={refresh}>读取云端版本</button><button disabled={busy||!remote} onClick={push}>上传本地媒体库</button><button disabled={busy||!remote} onClick={pull}>用已读取版本替换本地</button></div>
      <p className="hint">媒体库包含频道、收藏、最近播放和点播进度。上传遇到版本冲突时会保留双方数据，请重新读取后选择要保留的版本。</p>
      <button disabled={busy} onClick={()=>void run(()=>homeRequest<{code:string;expiresAt:number}>("pairings",{},session.token),r=>setCode(r.code))}>生成 5 分钟配对码</button>{code&&<output>{code}</output>}
      <button disabled={busy} onClick={()=>void run(()=>homeRequest<Device[]>("devices",undefined,session.token),setDevices)}>查看已授权设备</button>
      <div className="panel-actions"><button disabled={busy} onClick={()=>void run(()=>homeRequest<{id:string;name:string;online:boolean}[]>("remote/devices",undefined,session.token),setOnline)}>刷新遥控设备</button>
      <select aria-label="遥控目标设备" value={target} onChange={e=>setTarget(e.target.value)}><option value="">选择设备</option>{online.map(d=><option key={d.id} value={d.id}>{d.name}{d.online?" · 在线":" · 离线"}</option>)}</select>
      {["PLAY","PAUSE"].map(type=><button key={type} disabled={busy||!target} onClick={()=>void run(()=>homeRequest<{id:string}>("remote/commands",{targetDeviceId:target,type},session.token),r=>setCommand(r.id))}>{type==="PLAY"?"远程播放":"远程暂停"}</button>)}
      <input aria-label="遥控跳转秒数" type="number" min="0" max="604799" value={seek} onChange={e=>setSeek(Number(e.target.value))}/><button disabled={busy||!target} onClick={()=>void run(()=>homeRequest<{id:string}>("remote/commands",{targetDeviceId:target,type:"SEEK",position:seek},session.token),r=>setCommand(r.id))}>远程跳转</button>
      <input aria-label="远程媒体地址" type="url" value={media} onChange={e=>setMedia(e.target.value)}/><button disabled={busy||!target||!media} onClick={()=>void run(()=>homeRequest<{id:string}>("remote/commands",{targetDeviceId:target,type:"LOAD",url:media},session.token),r=>setCommand(r.id))}>远程加载媒体</button>
      <button disabled={busy||!command} onClick={()=>void run(()=>homeRequest<{state:string;message?:string}>("remote/commands/"+command,undefined,session.token),r=>setNotice(r.state+(r.message?" · "+r.message:"")))}>查看遥控结果</button></div>
      {devices.map(d=><div className="channel-line" key={d.id}><span>{d.name}{d.current?"（当前设备）":""}</span><button disabled={busy} onClick={()=>void run(()=>homeRequest("devices/"+d.id+"/revoke",{},session.token),()=>{if(d.current)logout();else setDevices(items=>items.filter(x=>x.id!==d.id));})}>撤销授权</button></div>)}
    </>}
    <div className="panel-actions"><button onClick={download}>导出本地备份</button><label className="file-picker">恢复备份<input type="file" accept=".json" onChange={e=>{const file=e.target.files?.[0];if(file&&file.size>2000000){setError("备份最多 2 MB");e.target.value="";return;}if(file)void file.text().then(text=>{const data:unknown=JSON.parse(text);if(!data||typeof data!=="object"||!("version" in data)||data.version!==1||!("channels" in data)||!Array.isArray(data.channels)||!("favorites" in data)||!Array.isArray(data.favorites)||!("recent" in data)||!Array.isArray(data.recent)||!("positions" in data)||!data.positions||typeof data.positions!=="object")throw Error("备份版本无效");onRestore(normalizeLibrary(data));setNotice("已恢复本地备份，尚未上传。");}).catch(err=>setError(err instanceof Error?err.message:"备份无效"));e.target.value="";}}/></label></div>
    {notice&&<p role="status">{notice}</p>}{error&&<p className="alert" role="alert">{error}</p>}
  </section>;
}
