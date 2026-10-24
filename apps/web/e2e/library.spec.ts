import { test,expect } from "@playwright/test";
import type { Page } from "@playwright/test";

const media="http://127.0.0.1:8765/fixture.mp4";
const hls="http://127.0.0.1:8765/fixture.m3u8";
const key="tv-next-library-v1";
async function importPlaylist(page:Page){
  await page.getByRole("textbox",{name:"M3U 内容"}).fill(`#EXTM3U\n#EXTINF:-1 group-title="Fixture",Fixture MP4\n${media}\n#EXTINF:-1 group-title="Fixture",Fixture HLS\n${hls}`);
  const response=page.waitForResponse(r=>r.url().endsWith("/api/v1/playlists/parse")&&r.request().method()==="POST");
  await page.getByRole("button",{name:"导入频道",exact:true}).click();expect((await response).status()).toBe(200);
  await expect(page.locator("button.channel").filter({hasText:"Fixture MP4"})).toBeVisible();
}
async function select(page:Page,name:string){
  await page.locator("button.channel").filter({hasText:name}).first().click();
  await expect.poll(()=>page.locator("video").evaluate(v=>(v as HTMLVideoElement).readyState)).toBeGreaterThanOrEqual(2);
  await page.locator("video").scrollIntoViewIfNeeded();
}
test.beforeEach(async({page})=>{await page.goto("/");});

test("real REST import, decoded MP4, favorites and original-URL resume survive reload",async({page})=>{
  await importPlaylist(page);await select(page,"Fixture MP4");
  await page.locator("video").evaluate(async node=>{const v=node as HTMLVideoElement;v.muted=true;await v.play();});
  await expect.poll(()=>page.locator("video").evaluate(v=>(v as HTMLVideoElement).currentTime),{timeout:10000}).toBeGreaterThan(0.2);
  await page.getByRole("button",{name:"☆ 收藏此频道",exact:true}).click();
  await page.locator("video").evaluate(async node=>{const v=node as HTMLVideoElement;v.pause();v.currentTime=20;await new Promise<void>(resolve=>v.addEventListener("seeked",()=>resolve(),{once:true}));v.dispatchEvent(new Event("pause"));});
  await expect.poll(()=>page.evaluate(({key,media})=>JSON.parse(localStorage.getItem(key)||"{}").positions?.[media]||0,{key,media})).toBeGreaterThanOrEqual(19);
  await page.reload();await page.getByRole("button",{name:/我的收藏/}).click();await select(page,"Fixture MP4");
  await expect.poll(()=>page.locator("video").evaluate(v=>(v as HTMLVideoElement).currentTime)).toBeGreaterThanOrEqual(19);
  const stored=await page.evaluate(key=>JSON.parse(localStorage.getItem(key)||"{}"),key);
  expect(stored.favorites).toContain(media);expect(stored.recent[0].channel.url).toBe(media);
  await page.getByLabel("播放速度").selectOption("1.5");expect(await page.locator("video").evaluate(v=>(v as HTMLVideoElement).playbackRate)).toBe(1.5);
});

test("HLS demux/decoding uses local synthetic segments and preserves the selection",async({page})=>{
  await importPlaylist(page);await select(page,"Fixture HLS");
  await page.locator("video").evaluate(async node=>{const v=node as HTMLVideoElement;v.muted=true;await v.play();});
  await expect.poll(()=>page.locator("video").evaluate(v=>(v as HTMLVideoElement).currentTime),{timeout:10000}).toBeGreaterThan(0.2);
  await expect(page.locator(".player-header")).toContainText("Fixture HLS");
  expect(await page.locator("video").evaluate(v=>(v as HTMLVideoElement).videoWidth)).toBe(160);
});

test("invalid imports and inaccessible media report errors without erasing saved channels",async({page})=>{
  await importPlaylist(page);
  await page.getByRole("textbox",{name:"M3U 内容"}).fill("#EXTM3U\n#EXTINF:-1,Unsupported\nfile:///private/video.mp4");
  await page.getByRole("button",{name:"导入频道",exact:true}).click();
  await expect(page.getByRole("alert")).toContainText("未找到");
  await expect(page.locator("button.channel").filter({hasText:"Fixture MP4"})).toBeVisible();
  await page.getByLabel("快速播放",{exact:true}).fill("http://127.0.0.1:8765/missing.mp4");
  await page.getByRole("button",{name:"播放 URL →",exact:true}).click();
  await expect(page.locator(".player-error")).toContainText("播放失败");
  await page.reload();expect(await page.locator("button.channel").filter({hasText:"Fixture MP4"}).count()).toBe(1);
});

test("local media, subtitle import and keyboard navigation work without storing a local file URL",async({page})=>{
  await page.setViewportSize({width:390,height:844});
  await page.getByLabel("快速播放",{exact:true}).focus();await page.keyboard.press("Tab");await expect(page.getByRole("button",{name:"播放 URL →",exact:true})).toBeFocused();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
  const fixture=await page.request.get(media);expect(fixture.ok()).toBeTruthy();
  await page.getByLabel("从本机播放视频 / 音频").setInputFiles({name:"owned.mp4",mimeType:"video/mp4",buffer:await fixture.body()});
  await expect.poll(()=>page.locator("video").evaluate(v=>(v as HTMLVideoElement).readyState)).toBeGreaterThanOrEqual(2);
  await page.getByLabel("加载 SRT / VTT").setInputFiles({name:"owned.srt",mimeType:"text/plain",buffer:Buffer.from("1\n00:00:00,000 --> 00:00:10,000\nFixture subtitle\n")});
  await expect(page.getByRole("button",{name:"移除字幕",exact:true})).toBeVisible();
  await expect.poll(()=>page.locator("video track").count()).toBe(1);
  expect(await page.evaluate(key=>(localStorage.getItem(key)||"").includes("blob:"),key)).toBe(false);
  await page.reload();await expect(page.locator(".player-header")).toContainText("尚未选择媒体");
});


test("keyboard users can skip navigation, identify active view and reach M3U file picker",async({page})=>{
  await page.keyboard.press("Tab");
  const skip=page.getByRole("link",{name:"跳转到主要内容"});
  await expect(skip).toBeFocused();
  await expect(skip).toBeVisible();
  await page.keyboard.press("Enter");
  await expect(page.locator("#main-content")).toBeFocused();

  const playlist=page.getByRole("button",{name:/播放列表/});
  const favorites=page.getByRole("button",{name:/我的收藏/});
  await expect(playlist).toHaveAttribute("aria-pressed","true");
  await favorites.click();
  await expect(favorites).toHaveAttribute("aria-pressed","true");
  await expect(playlist).toHaveAttribute("aria-pressed","false");
  await playlist.click();

  await page.getByRole("textbox",{name:"M3U 内容"}).focus();
  await page.keyboard.press("Tab");
  const picker=page.getByLabel("选择 M3U 文件");
  await expect(picker).toBeFocused();
  await expect(page.locator(".file-picker").filter({has:picker})).toHaveCSS("outline-style","solid");
  await picker.setInputFiles({name:"owned.m3u",mimeType:"text/plain",buffer:Buffer.from(`#EXTM3U\\n#EXTINF:-1,Fixture MP4\\n${media}`)});
  await expect(page.getByRole("textbox",{name:"M3U 内容"})).toContainText("Fixture MP4");
  await page.getByRole("button",{name:"导入频道",exact:true}).click();
  const channel=page.locator("button.channel").filter({hasText:"Fixture MP4"});
  await expect(channel).toBeVisible();
  await expect(channel).toHaveAttribute("aria-pressed","false");
  await channel.click();
  await expect(channel).toHaveAttribute("aria-pressed","true");
});
