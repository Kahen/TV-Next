// @vitest-environment jsdom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import SubscriptionBrowser from "./SubscriptionBrowser";
import CloudBrowser from "./CloudBrowser";
import { requestJson } from "./api";
vi.mock("./api",()=>({requestJson:vi.fn()}));
const request=vi.mocked(requestJson);
const doc={content:'{"sites":[]}',url:"https://example.org/config.json",sites:[{key:"cloud",name:"Cloud",type:4,searchable:true,hidden:false,support:"http-spider"},{key:"android",name:"Android",type:3,searchable:true,hidden:false,support:"requires-spider-runtime"}],warnings:[],depots:[],liveCount:0};
afterEach(cleanup);beforeEach(()=>{request.mockReset();});
it("loads original subscription and resolves cloud episode with playback metadata",async()=>{
  const onPlay=vi.fn();
  request.mockResolvedValueOnce(doc)
    .mockResolvedValueOnce({categories:[],items:[{id:"1",name:"Movie"}],total:1,page:1,hasMore:false})
    .mockResolvedValueOnce({item:{id:"1",name:"Movie"},description:"own content",lines:[{name:"Cloud",episodes:[{name:"E1",playable:true}]}]})
    .mockResolvedValueOnce({url:"https://example.org/video.mp4",name:"E1",lineName:"Cloud",headers:{Referer:"https://example.org/"},danmaku:[{name:"弹幕",url:"https://example.org/dm.xml"}],subtitles:[]});
  render(<SubscriptionBrowser onPlay={onPlay}/>);
  fireEvent.change(screen.getByLabelText("订阅配置"),{target:{value:'{"sites":[]}'}});
  fireEvent.click(screen.getByText("加载订阅"));
  const cloud=await screen.findByRole("button",{name:"Cloud"});
  expect((screen.getByRole("button",{name:/Android/}) as HTMLButtonElement).disabled).toBe(true);
  fireEvent.click(cloud);fireEvent.click(await screen.findByText("Movie"));
  fireEvent.click(await screen.findByText("E1"));
  await waitFor(()=>expect(onPlay).toHaveBeenCalledWith(expect.objectContaining({url:"https://example.org/video.mp4",danmaku:[{name:"弹幕",url:"https://example.org/dm.xml"}]})));
  expect(request.mock.calls[1][1]).toEqual(expect.objectContaining({content:doc.content,url:doc.url,siteKey:"cloud"}));
});
it("cloud navigation keeps tokens in requests and disconnect clears credentials",async()=>{
  request.mockResolvedValueOnce({path:"/",entries:[{name:"Series",directory:true,size:0}],page:1,hasMore:false})
    .mockResolvedValueOnce({path:"/Series",entries:[{name:"E1.mp4",directory:false,size:100}],page:1,hasMore:false})
    .mockResolvedValueOnce({url:"https://example.org/E1.mp4",name:"E1.mp4",headers:{}});
  const onPlay=vi.fn();render(<CloudBrowser onPlay={onPlay}/>);
  fireEvent.change(screen.getByLabelText("网盘服务地址"),{target:{value:"https://openlist.example/"}});
  fireEvent.change(screen.getByLabelText("网盘访问令牌"),{target:{value:"secret-own-token"}});
  fireEvent.click(screen.getByText("打开网盘"));
  fireEvent.click(await screen.findByText(/Series/));
  fireEvent.click(await screen.findByText(/E1.mp4/));
  await waitFor(()=>expect(onPlay).toHaveBeenCalled());
  expect(request.mock.calls[2][1]).toEqual(expect.objectContaining({path:"/Series/E1.mp4",token:"secret-own-token"}));
  expect(window.localStorage.length).toBe(0);
  fireEvent.click(screen.getByText("断开并清除凭据"));
  expect((screen.getByLabelText("网盘访问令牌") as HTMLInputElement).value).toBe("");
});
it("a canceled subscription response cannot replace current state",async()=>{
  let resolve!:(value:unknown)=>void;
  request.mockImplementationOnce(()=>new Promise(r=>{resolve=r;}));
  render(<SubscriptionBrowser onPlay={()=>{}}/>);
  fireEvent.click(screen.getByText("加载订阅"));fireEvent.click(screen.getByText("取消请求"));
  resolve(doc);await new Promise(r=>setTimeout(r,0));
  expect(screen.queryByRole("button",{name:"Cloud"})).toBeNull();
});
