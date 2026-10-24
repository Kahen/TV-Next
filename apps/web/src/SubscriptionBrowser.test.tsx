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
it("applies original filter init, retains chosen values for pagination and resets at category changes",async()=>{
  const definitions={movie:[{key:"area",name:"地区",init:"cn",value:[{n:"全部",v:""},{n:"中国",v:"cn"},{n:"美国",v:"us"}]}],series:[{key:"sort",name:"排序",value:[{n:"默认",v:""},{n:"最新",v:"time"}]}]};
  request.mockImplementation(async(path,body)=>{
    if(path.endsWith("/load"))return doc;
    const r=body as {page?:number};
    return {categories:[{id:"movie",name:"电影"},{id:"series",name:"剧集"}],items:[],total:30,page:r.page||1,pageSize:10,hasMore:true,provider:"cloud",filters:path.endsWith("/home")?definitions:{}};
  });
  render(<SubscriptionBrowser onPlay={()=>{}}/>);
  fireEvent.click(screen.getByText("加载订阅"));fireEvent.click(await screen.findByRole("button",{name:"Cloud"}));
  fireEvent.click(await screen.findByRole("button",{name:"电影"}));
  const area=await screen.findByLabelText("筛选：地区");expect((area as HTMLSelectElement).value).toBe("cn");
  expect(request.mock.calls.at(-1)?.[1]).toEqual(expect.objectContaining({categoryId:"movie",filters:{area:"cn"}}));
  fireEvent.change(area,{target:{value:"us"}});
  expect(screen.getByRole("status").textContent).toContain("筛选尚未应用");
  // Moving to page 2 must use the committed China filter, not the unsubmitted US draft.
  fireEvent.click(screen.getByRole("button",{name:"下一页"}));
  await waitFor(()=>expect(request.mock.calls.at(-1)?.[1]).toEqual(expect.objectContaining({page:2,filters:{area:"cn"}})));
  await waitFor(()=>expect((screen.getByLabelText("筛选：地区") as HTMLSelectElement).value).toBe("us"));
  fireEvent.click(screen.getByRole("button",{name:"应用筛选"}));
  await waitFor(()=>expect(request.mock.calls.at(-1)?.[1]).toEqual(expect.objectContaining({page:1,filters:{area:"us"}})));
  await waitFor(()=>expect((screen.getByRole("button",{name:"下一页"}) as HTMLButtonElement).disabled).toBe(false));
  fireEvent.click(screen.getByRole("button",{name:"下一页"}));
  await waitFor(()=>expect(request.mock.calls.at(-1)?.[1]).toEqual(expect.objectContaining({page:2,filters:{area:"us"}})));
  await waitFor(()=>expect((screen.getByRole("button",{name:"剧集"}) as HTMLButtonElement).disabled).toBe(false));fireEvent.click(screen.getByRole("button",{name:"剧集"}));
  await screen.findByLabelText("筛选：排序");expect(request.mock.calls.at(-1)?.[1]).toEqual(expect.objectContaining({page:1,categoryId:"series",filters:{sort:""}}));
});
it("uses a bearer header argument and explicitly bypasses cached searches on refresh",async()=>{
  const session={token:"x".repeat(43),user:{id:"u",username:"own"},device:{id:"d",name:"Web",createdAt:1,expiresAt:Date.now()+600000,current:true}};
  request.mockImplementation(async(path,body)=>path.endsWith("/load")?doc:{categories:[],items:[],total:0,page:(body as {page?:number}).page||1,hasMore:false});
  render(<SubscriptionBrowser session={session} onPlay={()=>{}}/>);
  fireEvent.click(screen.getByText("加载订阅"));fireEvent.click(await screen.findByRole("button",{name:"Cloud"}));
  await waitFor(()=>expect((screen.getByRole("button",{name:"Cloud"}) as HTMLButtonElement).disabled).toBe(false));
  fireEvent.change(screen.getByLabelText("搜索订阅站点"),{target:{value:"owned query"}});fireEvent.click(screen.getByText("当前站点搜索"));
  const refresh=await screen.findByText("刷新搜索结果");await waitFor(()=>expect((refresh as HTMLButtonElement).disabled).toBe(false));fireEvent.click(refresh);
  await waitFor(()=>expect(request.mock.calls.at(-1)?.[1]).toEqual(expect.objectContaining({bypassCache:true,query:"owned query"})));
  expect(request.mock.calls.at(-1)?.[3]).toBe(session.token);
});
