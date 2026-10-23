import { useEffect,useRef,useState } from "react";
import { homeRequest } from "./homeApi";
import type { HomeSession } from "./homeApi";
export interface RemotePacket {id:string;type:"PLAY"|"PAUSE"|"SEEK"|"LOAD";position?:number|null;url?:string|null}
export function useRemoteControl(session:HomeSession|null,receive:(packet:RemotePacket)=>Promise<void>):string{
  const handler=useRef(receive);handler.current=receive;
  const [state,setState]=useState("未连接");
  useEffect(()=>{
    if(!session){setState("未连接");return;}
    let stopped=false;let socket:WebSocket|null=null;let retry=0;let timer:ReturnType<typeof setTimeout>|undefined;let heartbeat:ReturnType<typeof setInterval>|undefined;
    function reconnect(){if(stopped)return;setState("正在重连");clearInterval(heartbeat);timer=setTimeout(()=>void connect(),Math.min(30000,1000*2**Math.min(retry++,5)));}
    async function connect(){
      try{
        const result=await homeRequest<{ticket:string}>("remote/ticket",{},session!.token);if(stopped)return;
        const base=new URL(import.meta.env.VITE_API_BASE_URL||window.location.origin,window.location.origin);base.protocol=base.protocol==="https:"?"wss:":"ws:";base.pathname=base.pathname.replace(/\/$/,"")+"/api/v1/home/remote/socket";base.search="?ticket="+encodeURIComponent(result.ticket);base.hash="";
        const peer=new WebSocket(base);socket=peer;
        peer.onopen=()=>{if(stopped){peer.close();return;}retry=0;setState("在线");heartbeat=setInterval(()=>{if(peer.readyState===WebSocket.OPEN)peer.send('{"type":"PING"}');},25000);};
        peer.onclose=reconnect;peer.onerror=()=>{if(!stopped)setState("连接失败");};
        peer.onmessage=async(event)=>{
          if(stopped||typeof event.data!=="string"||event.data.length>16384)return;
          let packet:RemotePacket;try{const value:unknown=JSON.parse(event.data);if(!value||typeof value!=="object"||!("type" in value))return;packet=value as RemotePacket;}catch{return;}
          if(packet.type as string==="PONG")return;
          let success=true,message="";
          try{if(typeof packet.id!=="string"||!["PLAY","PAUSE","SEEK","LOAD"].includes(packet.type))throw Error("未知遥控操作");await handler.current(packet);}catch(e){success=false;message=e instanceof Error?e.message:"操作失败";}
          if(peer.readyState===WebSocket.OPEN)peer.send(JSON.stringify({type:"ACK",id:packet.id,success,message:message.slice(0,200)}));
        };
      }catch{reconnect();}
    }
    void connect();
    return()=>{stopped=true;clearTimeout(timer);clearInterval(heartbeat);socket?.close();};
  },[session?.token]);
  return state;
}
