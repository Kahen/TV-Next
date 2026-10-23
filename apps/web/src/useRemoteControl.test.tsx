// @vitest-environment jsdom
import { afterEach,expect,it,vi } from "vitest";
import { act,cleanup,renderHook,waitFor } from "@testing-library/react";
import { useRemoteControl } from "./useRemoteControl";
import { homeRequest } from "./homeApi";
import type { HomeSession } from "./homeApi";
vi.mock("./homeApi",()=>({homeRequest:vi.fn()}));
class Peer {
  static OPEN=1;static peers:Peer[]=[];
  readyState=1;sent:string[]=[];onopen:(()=>void)|null=null;onclose:(()=>void)|null=null;onerror:(()=>void)|null=null;onmessage:((event:MessageEvent)=>void)|null=null;
  url:string;
  constructor(url:string|URL){this.url=String(url);Peer.peers.push(this);}
  send(value:string){this.sent.push(value);}
  close(){this.readyState=3;this.onclose?.();}
}
const session:HomeSession={token:"a".repeat(43),user:{id:"u",username:"own"},device:{id:"d",name:"Browser",createdAt:1,expiresAt:Date.now()+600000,current:true}};
afterEach(()=>{cleanup();Peer.peers=[];vi.unstubAllGlobals();vi.mocked(homeRequest).mockReset();});
it("uses one-use ticket instead of reusable token in socket URL and ACKs applied commands",async()=>{
  vi.stubGlobal("WebSocket",Peer);vi.mocked(homeRequest).mockResolvedValueOnce({ticket:"b".repeat(43)});
  const receive=vi.fn().mockResolvedValue(undefined);const result=renderHook(({s})=>useRemoteControl(s,receive),{initialProps:{s:session as HomeSession|null}});
  await waitFor(()=>expect(Peer.peers).toHaveLength(1));const peer=Peer.peers[0];
  expect(peer.url).toContain("ticket="+"b".repeat(43));expect(peer.url).not.toContain(session.token);
  act(()=>peer.onopen?.());await act(async()=>peer.onmessage?.(new MessageEvent("message",{data:JSON.stringify({id:"command-1",type:"SEEK",position:45})})));
  await waitFor(()=>expect(peer.sent.map(x=>JSON.parse(x))).toContainEqual({type:"ACK",id:"command-1",success:true,message:""}));
  expect(receive).toHaveBeenCalledWith(expect.objectContaining({position:45}));
  result.rerender({s:null});expect(peer.readyState).toBe(3);expect(result.result.current).toBe("未连接");
});
it("ignores malformed payloads and reports playback restriction as rejection",async()=>{
  vi.stubGlobal("WebSocket",Peer);vi.mocked(homeRequest).mockResolvedValueOnce({ticket:"b".repeat(43)});
  const receive=vi.fn().mockRejectedValue(new Error("Autoplay blocked"));renderHook(()=>useRemoteControl(session,receive));
  await waitFor(()=>expect(Peer.peers).toHaveLength(1));const peer=Peer.peers[0];
  await act(async()=>peer.onmessage?.(new MessageEvent("message",{data:"null"})));expect(receive).not.toHaveBeenCalled();
  await act(async()=>peer.onmessage?.(new MessageEvent("message",{data:'{"id":"command-2","type":"PLAY"}'})));
  await waitFor(()=>expect(peer.sent.map(x=>JSON.parse(x))).toContainEqual({type:"ACK",id:"command-2",success:false,message:"Autoplay blocked"}));
});
