// @vitest-environment jsdom
import { afterEach,beforeEach,expect,it,vi } from "vitest";
import { useState } from "react";
import { cleanup,fireEvent,render,screen,waitFor } from "@testing-library/react";
import HomeServerPanel from "./HomeServerPanel";
import { homeRequest,loadHomeSession,saveHomeSession } from "./homeApi";
import type { HomeSession } from "./homeApi";
import { emptyLibrary } from "./library";
vi.mock("./homeApi",async()=>{const original=await vi.importActual<typeof import("./homeApi")>("./homeApi");return {...original,homeRequest:vi.fn()};});
const request=vi.mocked(homeRequest);
const session:HomeSession={token:"a".repeat(43),user:{id:"u1",username:"own"},device:{id:"d1",name:"Browser",createdAt:1,expiresAt:Date.now()+600000,current:true}};
afterEach(()=>{cleanup();window.sessionStorage.clear();window.localStorage.clear();});beforeEach(()=>request.mockReset());
function Wrapper({onRestore,initial=session}:{onRestore:ReturnType<typeof vi.fn>;initial?:HomeSession|null}){const [state,setState]=useState(initial);return <HomeServerPanel library={emptyLibrary()} onRestore={onRestore} session={state} onSessionChange={setState}/>;}
it("reads without replacing local data, uses revision CAS, and does not overwrite after conflict",async()=>{
  const restore=vi.fn();const snapshot={...emptyLibrary(),channels:[{name:"Cloud",url:"https://example.org/a",group:"Own"}]};
  request.mockResolvedValueOnce({revision:3,updatedAt:1,library:snapshot}).mockRejectedValueOnce(new Error("Library changed on another device"));
  render(<Wrapper onRestore={restore}/>);
  fireEvent.click(screen.getByText("读取云端版本"));
  await screen.findByText(/已读取云端版本 3/);expect(restore).not.toHaveBeenCalled();
  fireEvent.click(screen.getByText("上传本地媒体库"));
  await screen.findByRole("alert");expect(request.mock.calls[1][1]).toEqual(expect.objectContaining({expectedRevision:3}));expect(restore).not.toHaveBeenCalled();
  fireEvent.click(screen.getByText("用已读取版本替换本地"));expect(restore).toHaveBeenCalledWith(expect.objectContaining({channels:snapshot.channels}));
});
it("pairing claims a device and revoking the current device signs out",async()=>{
  request.mockResolvedValueOnce(session).mockResolvedValueOnce([session.device]).mockResolvedValueOnce({revoked:true});
  render(<Wrapper initial={null} onRestore={vi.fn()}/>);
  fireEvent.change(screen.getByLabelText("配对码"),{target:{value:"1234-5678-ABCD-EF01"}});
  fireEvent.click(screen.getByText("通过配对码登录"));await screen.findByText("own · Browser");
  fireEvent.click(screen.getByText("查看已授权设备"));await screen.findByText("Browser（当前设备）");
  fireEvent.click(screen.getByText("撤销授权"));await screen.findByLabelText("密码");
  expect(request.mock.calls[2][0]).toBe("devices/d1/revoke");
});
it("rejects wrong-version backup instead of clearing the local library",async()=>{
  const restore=vi.fn();render(<Wrapper onRestore={restore}/>);
  const file=new File(['{}'],"bad.json",{type:"application/json"});Object.assign(file,{text:()=>Promise.resolve('{}')});
  fireEvent.change(screen.getByLabelText("恢复备份"),{target:{files:[file]}});
  await waitFor(()=>expect(screen.getByRole("alert").textContent).toContain("备份版本无效"));expect(restore).not.toHaveBeenCalled();
});
it("persists device session in this tab only and rejects expired sessions",()=>{
  saveHomeSession(session);expect(loadHomeSession()?.token).toBe(session.token);expect(window.localStorage.length).toBe(0);
  saveHomeSession({...session,device:{...session.device,expiresAt:1}});expect(loadHomeSession()).toBeNull();saveHomeSession(null);expect(loadHomeSession()).toBeNull();
});

it("signs out immediately, clears prior account controls and revokes only the old token",async()=>{
  request.mockResolvedValueOnce([{id:"old-target",name:"Old receiver",online:true}]).mockReturnValueOnce(new Promise(()=>{}));
  render(<Wrapper onRestore={vi.fn()}/>);
  fireEvent.click(screen.getByText("刷新遥控设备"));await screen.findByText("Old receiver · 在线");
  fireEvent.change(screen.getByLabelText("遥控目标设备"),{target:{value:"old-target"}});
  fireEvent.change(screen.getByLabelText("远程媒体地址"),{target:{value:"https://example.org/private.mp4"}});
  fireEvent.click(screen.getByText("退出本页"));
  expect(screen.getByLabelText("密码")).toBeTruthy();
  expect(screen.queryByText("Old receiver · 在线")).toBeNull();
  expect(request.mock.calls[1]).toEqual(["devices/d1/revoke",{},session.token]);
  request.mockResolvedValueOnce({...session,token:"b".repeat(43),user:{id:"u2",username:"next"}});
  fireEvent.change(screen.getByLabelText("账号"),{target:{value:"next"}});
  fireEvent.change(screen.getByLabelText("密码"),{target:{value:"another-password"}});
  fireEvent.click(screen.getByText("登录"));await screen.findByText("next · Browser");
  expect((screen.getByLabelText("遥控目标设备") as HTMLSelectElement).value).toBe("");
  expect((screen.getByLabelText("远程媒体地址") as HTMLInputElement).value).toBe("");
});
