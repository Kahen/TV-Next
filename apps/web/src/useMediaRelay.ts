import { useEffect,useState } from "react";
import { homeRequest } from "./homeApi";
import type { HomeSession } from "./homeApi";
import type { Channel } from "./api";

export function mediaRelayAddress(path:string):{url:string;ticket:string} {
  if(!/^\/api\/v1\/home\/media\/[A-Za-z0-9_-]{43}\/0$/.test(path))throw Error("服务器返回的媒体会话地址无效");
  const base=new URL(import.meta.env.VITE_API_BASE_URL||window.location.origin,window.location.origin);
  if(!["http:","https:"].includes(base.protocol)||base.username||base.password)throw Error("媒体服务器地址无效");
  return {url:new URL(path,base).href,ticket:path.split("/")[5]};
}
export function useMediaRelay(channel:Channel|null,session:HomeSession|null){
  const [result,setResult]=useState<{channel:Channel;token:string;url?:string;hls?:boolean;error?:string}|null>(null);
  const required=!!channel&&Object.keys(channel.headers||{}).length>0&&!!session;
  useEffect(()=>{
    if(!required||!channel||!session){setResult(null);return;}
    let stopped=false;let ticket:string|undefined;
    const token=session.token;
    const close=()=>{if(ticket)void homeRequest("media/"+ticket+"/close",{},token).catch(()=>{});};
    setResult(null);
    void (async()=>{
      try{
        const response=await homeRequest<{path:string}>("media/sessions",{url:channel.url,headers:channel.headers},token);
        const address=mediaRelayAddress(response.path);ticket=address.ticket;
        if(stopped){close();return;}
        let hls=new URL(channel.url).pathname.toLowerCase().endsWith(".m3u8");
        try{const head=await fetch(address.url,{method:"HEAD",credentials:"omit",signal:AbortSignal.timeout(10000)});if(head.ok&&/mpegurl/i.test(head.headers.get("Content-Type")||""))hls=true;}catch{/* GET remains usable when a source rejects HEAD. */}
        if(stopped){close();return;}
        setResult({channel,token,url:address.url,hls});
      }catch(error){if(!stopped)setResult({channel,token,error:error instanceof Error?error.message:"媒体中转连接失败"});}
    })();
    return()=>{stopped=true;close();};
  },[channel,session?.token,required]);
  const current=result?.channel===channel&&result?.token===session?.token?result:null;
  return {required,pending:required&&!current,url:current?.url,hls:current?.hls,error:current?.error};
}
