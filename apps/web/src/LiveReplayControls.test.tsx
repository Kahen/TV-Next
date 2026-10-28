// @vitest-environment jsdom
import { afterEach, expect, it, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import LiveReplayControls, { timeshiftRange } from "./LiveReplayControls";
import type { Channel } from "./api";
import { addRecent, emptyLibrary, normalizeLibrary } from "./library";
import golden from "../../../fixtures/fongmi-live-replay-golden.json";

const session = { token:"owner-token",user:{id:"u",username:"Owner"},device:{id:"d",name:"Web",createdAt:0,expiresAt:9e12,current:true} };
const channel: Channel = { name:"News",group:"Live",url:golden.liveUrl,timeshift:golden.timeshift,catchup:golden.catchup,headers:{Cookie:"private-live"} };
const replay = { path:"/api/v1/home/media/"+"a".repeat(43)+"/0",expiresAt:golden.now+3600000,hls:true,time:0 };
afterEach(() => { cleanup();vi.restoreAllMocks();vi.unstubAllGlobals(); });

it("uses the shared original millisecond range and rejects malformed declarations", () => {
  expect(timeshiftRange(channel,golden.now)).toEqual([golden.time,golden.now]);
  expect(timeshiftRange({...channel,timeshift:{...golden.timeshift,window:-1}},golden.now)).toBeNull();
  expect(timeshiftRange({...channel,timeshift:{...golden.timeshift,start:golden.now}},golden.now)).toBeNull();
});

it("requests an authenticated zero sentinel, validates the capability and retains original channel identity", async () => {
  vi.spyOn(Date,"now").mockReturnValue(golden.now);
  const fetcher=vi.fn(async()=>({ok:true,json:async()=>replay}));vi.stubGlobal("fetch",fetcher);
  const play=vi.fn();render(<LiveReplayControls channel={channel} session={session} onPlay={play}/>);
  fireEvent.click(screen.getByRole("button",{name:"回到直播"}));
  await waitFor(()=>expect(play).toHaveBeenCalledOnce());
  const [path,options]=fetcher.mock.calls[0] as unknown as [string,RequestInit];
  expect(path).toBe("/api/v1/subscriptions/replay");expect(options.headers).toHaveProperty("Authorization","Bearer owner-token");
  const body=JSON.parse(String(options.body));expect(body.time).toBe(0);expect(body.channel.timeshift).toEqual(golden.timeshift);
  expect(play).toHaveBeenCalledWith({...channel,replay});
});

it("retains current playback on a provider failure and does not issue requests without a session", async () => {
  vi.spyOn(Date,"now").mockReturnValue(golden.now);
  const play=vi.fn();const fetcher=vi.fn(async()=>({ok:false,status:422,json:async()=>({error:"Unsupported catchup mode"})}));vi.stubGlobal("fetch",fetcher);
  const view=render(<LiveReplayControls channel={channel} session={null} onPlay={play}/>);
  expect(screen.getByRole("button",{name:"回到直播"}).hasAttribute("disabled")).toBe(true);expect(fetcher).not.toHaveBeenCalled();
  view.rerender(<LiveReplayControls channel={channel} session={session} onPlay={play}/>);
  fireEvent.click(screen.getByRole("button",{name:"回到直播"}));
  expect((await screen.findByRole("alert")).textContent).toContain("Unsupported catchup mode");expect(play).not.toHaveBeenCalled();
});

it("does not apply a superseded response and closes its returned capability", async () => {
  vi.spyOn(Date,"now").mockReturnValue(golden.now);
  let finish!:(v:unknown)=>void;
  const fetcher=vi.fn((path:string)=>path.endsWith("/replay")?new Promise(resolve=>{finish=resolve;}):Promise.resolve({ok:true,json:async()=>({closed:true})}));
  vi.stubGlobal("fetch",fetcher);const play=vi.fn();
  const view=render(<LiveReplayControls channel={channel} session={session} onPlay={play}/>);
  fireEvent.click(screen.getByRole("button",{name:"回到直播"}));
  view.rerender(<LiveReplayControls channel={{...channel,url:"https://example.org/another"}} session={session} onPlay={play}/>);
  await act(async()=>{finish({ok:true,json:async()=>replay});});
  expect(play).not.toHaveBeenCalled();expect(fetcher.mock.calls.some(([url])=>url.endsWith("/close"))).toBe(true);
});

it("sends EPG catchup bounds separately and never persists provider replay templates or capabilities", async () => {
  vi.spyOn(Date,"now").mockReturnValue(golden.now);
  const fetcher=vi.fn(async()=>({ok:true,json:async()=>replay}));vi.stubGlobal("fetch",fetcher);
  const play=vi.fn();render(<LiveReplayControls channel={channel} session={session} onPlay={play}
    programme={{start:new Date(golden.time).toISOString(),stop:new Date(golden.stop).toISOString(),title:"Earlier news"}}/>);
  fireEvent.click(screen.getByRole("button",{name:"回看 · Earlier news"}));
  await waitFor(()=>expect(play).toHaveBeenCalledOnce());
  const [,options]=fetcher.mock.calls[0] as unknown as [string,RequestInit];const body=JSON.parse(String(options.body));
  expect(body.time).toBe(golden.time);expect(body.stop).toBe(golden.stop);
  const saved=normalizeLibrary(addRecent({...emptyLibrary(),channels:[channel]},{...channel,replay}));
  expect(saved.channels[0].timeshift).toBeUndefined();expect(saved.channels[0].catchup).toBeUndefined();
  expect(saved.recent[0].channel.replay).toBeUndefined();expect(saved.recent[0].channel.url).toBe(golden.liveUrl);
});

it("rejects server capabilities outside the configured relay path", async () => {
  vi.spyOn(Date,"now").mockReturnValue(golden.now);vi.stubGlobal("fetch",vi.fn(async()=>({ok:true,json:async()=>({...replay,path:"https://attacker.invalid/"})})));
  const play=vi.fn();render(<LiveReplayControls channel={channel} session={session} onPlay={play}/>);
  fireEvent.click(screen.getByRole("button",{name:"回到直播"}));await screen.findByRole("alert");expect(play).not.toHaveBeenCalled();
});
