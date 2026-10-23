// @vitest-environment jsdom
import { afterEach,expect,it,vi } from "vitest";
import { cleanup,fireEvent,render,screen,waitFor } from "@testing-library/react";
import EpgFeeds from "./EpgFeeds";
import type { HomeSession } from "./homeApi";
import type { Channel } from "./api";
const session:HomeSession={token:"test-token",user:{id:"owner",username:"user"},device:{id:"device",name:"Web",createdAt:0,expiresAt:9999999999999,current:true}};
const channels:Channel[]=[{name:"News",url:"https://example.org/news.m3u8",group:"Live",tvgId:"news"}];
const feed={id:"feed",name:"Fixture",url:"https://example.org/guide.xml.gz",intervalMinutes:360,enabled:true,updatedAt:1,nextRefresh:9999999999999,lastError:null,available:true};
afterEach(()=>{cleanup();vi.unstubAllGlobals();});
it("saves an opted-in feed with account token and requires explicit guide display",async()=>{
  const fetchMock=vi.fn(async(_path:string,init:RequestInit)=>({ok:true,json:async()=>init.method==="GET"?[feed]:feed}));vi.stubGlobal("fetch",fetchMock);
  const onGuide=vi.fn();render(<EpgFeeds session={session} channels={channels} hours={12} onGuide={onGuide}/>);
  expect(fetchMock).not.toHaveBeenCalled();
  fireEvent.change(screen.getByLabelText("节目表名称"),{target:{value:"Fixture"}});
  fireEvent.change(screen.getByLabelText("XMLTV 订阅网址"),{target:{value:feed.url}});
  fireEvent.click(screen.getByRole("button",{name:"保存订阅"}));
  await screen.findByText("Fixture",{selector:"strong"});
  expect(fetchMock.mock.calls[0][0]).toBe("/api/v1/home/epg/feeds");
  expect(fetchMock.mock.calls[0][1].headers).toHaveProperty("Authorization","Bearer test-token");
  expect(JSON.parse(String(fetchMock.mock.calls[0][1].body))).toEqual({name:"Fixture",url:feed.url,intervalMinutes:360,enabled:true});
  expect(onGuide).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button",{name:"显示节目表"}));
  await waitFor(()=>expect(onGuide).toHaveBeenCalledWith(feed,channels));
});
it("clears account feeds and ignores old account responses after logout",async()=>{
  let finish!:(value:unknown)=>void;const pending=new Promise(resolve=>{finish=resolve;});
  vi.stubGlobal("fetch",vi.fn(()=>pending));const onGuide=vi.fn();
  const view=render(<EpgFeeds session={session} channels={channels} hours={12} onGuide={onGuide}/>);
  fireEvent.click(screen.getByRole("button",{name:"读取订阅"}));
  view.rerender(<EpgFeeds session={null} channels={channels} hours={12} onGuide={onGuide}/>);
  finish({ok:true,json:async()=>[feed]});await new Promise(resolve=>setTimeout(resolve,0));
  expect(screen.queryByText("Fixture")).toBeNull();expect(onGuide).not.toHaveBeenCalled();
  expect(screen.getByText(/登录家庭服务器账号/)).toBeTruthy();
});
