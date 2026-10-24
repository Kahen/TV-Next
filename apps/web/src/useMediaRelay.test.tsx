// @vitest-environment jsdom
import { afterEach,expect,it,vi } from "vitest";
import { act,cleanup,renderHook,waitFor } from "@testing-library/react";
import { mediaRelayAddress,useMediaRelay } from "./useMediaRelay";
import { homeRequest } from "./homeApi";
import type { HomeSession } from "./homeApi";
vi.mock("./homeApi",()=>({homeRequest:vi.fn()}));
const session:HomeSession={token:"s".repeat(43),user:{id:"u",username:"own"},device:{id:"d",name:"Browser",createdAt:1,expiresAt:Date.now()+600000,current:true}};
const channel={name:"Private",url:"https://example.org/movie",group:"Own",headers:{Cookie:"source-private"}};
const path="/api/v1/home/media/"+"t".repeat(43)+"/0";
afterEach(()=>{cleanup();vi.mocked(homeRequest).mockReset();vi.unstubAllGlobals();});
it("accepts only registered same-server paths and never copies source or bearer secrets into the media URL",()=>{
  const result=mediaRelayAddress(path);expect(result.ticket).toBe("t".repeat(43));expect(new URL(result.url).origin).toBe(window.location.origin);
  for(const bad of ["https://evil.example/a","//evil.example/a",path+"?token=bad",path.replace("/0","/../0")])expect(()=>mediaRelayAddress(bad)).toThrow();
});
it("prepares a ticket, detects HLS by MIME and closes the exact session on logout",async()=>{
  vi.mocked(homeRequest).mockResolvedValue({path});vi.stubGlobal("fetch",vi.fn().mockResolvedValue({ok:true,headers:new Headers({"Content-Type":"application/vnd.apple.mpegurl"})}));
  const hook=renderHook(({s})=>useMediaRelay(channel,s),{initialProps:{s:session as HomeSession|null}});
  await waitFor(()=>expect(hook.result.current.url).toContain(path));expect(hook.result.current.hls).toBe(true);
  expect(vi.mocked(homeRequest).mock.calls[0]).toEqual(["media/sessions",{url:channel.url,headers:channel.headers},session.token]);
  expect(hook.result.current.url).not.toContain(session.token);expect(hook.result.current.url).not.toContain("source-private");
  hook.rerender({s:null});expect(hook.result.current.url).toBeUndefined();
  expect(vi.mocked(homeRequest).mock.calls.at(-1)).toEqual(["media/"+"t".repeat(43)+"/close",{},session.token]);
});
it("closes a late session response after switching media without replacing the new selection",async()=>{
  let finish:(v:{path:string})=>void=()=>{};
  vi.mocked(homeRequest).mockReturnValueOnce(new Promise(resolve=>{finish=resolve;})).mockResolvedValue({closed:true});
  const hook=renderHook(({c})=>useMediaRelay(c,session),{initialProps:{c:channel as typeof channel|null}});
  hook.rerender({c:null});await act(async()=>finish({path}));
  expect(hook.result.current.url).toBeUndefined();expect(hook.result.current.required).toBe(false);
  expect(vi.mocked(homeRequest).mock.calls.at(-1)?.[0]).toBe("media/"+"t".repeat(43)+"/close");
});
