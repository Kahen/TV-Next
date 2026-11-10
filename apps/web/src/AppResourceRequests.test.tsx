// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import App from "./App";
import { requestJson } from "./api";

vi.mock("./api", async original => ({
  ...await original<typeof import("./api")>(),
  requestJson: vi.fn()
}));

const mediaUrl = "https://example.org/shared.mp4";
const oldSubtitleUrl = "https://example.org/episode-1.srt";
const oldDanmakuUrl = "https://example.org/episode-1.xml";
const subtitle = {content: "1\n00:00:00,000 --> 00:00:02,000\nOwned subtitle\n"};

beforeEach(() => {
  vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
  vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue(null);
  vi.stubGlobal("URL", class extends URL {
    static createObjectURL = () => "blob:https://example.org/owned-subtitle";
    static revokeObjectURL = () => {};
  });
});

afterEach(() => {
  cleanup();
  window.localStorage.clear();
  vi.mocked(requestJson).mockReset();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it("discards late subtitle and danmaku outcomes after switching to an episode at the same URL", async () => {
  const pending = new Map<string, {
    signal?: AbortSignal;
    resolve: (value: {content: string}) => void;
    reject: (reason: Error) => void;
  }>();
  const title = {id: "owned", name: "Owned title"};
  vi.mocked(requestJson).mockImplementation(async (path, body, signal) => {
    const data = body as {episodeIndex?: number; url?: string};
    switch (path) {
      case "/api/v1/subscriptions/load":
        return {content: '{"sites":[]}', sites: [{key: "owned", name: "Owned site", type: 4, support: "http-spider"}],
          depots: [], warnings: [], liveCount: 0};
      case "/api/v1/subscriptions/home":
        return {categories: [], items: [title], total: 1, page: 1, hasMore: false};
      case "/api/v1/subscriptions/detail":
        return {item: title, lines: [{name: "Owned", episodes: [
          {name: "Episode 1", playable: true}, {name: "Episode 2", playable: true}
        ]}]};
      case "/api/v1/subscriptions/play":
        return data.episodeIndex === 0
          ? {url: mediaUrl, name: "Episode 1", lineName: "Owned",
            subtitles: [{name: "旧字幕.srt", url: oldSubtitleUrl}],
            danmaku: [{name: "旧弹幕", url: oldDanmakuUrl}]}
          : {url: mediaUrl, name: "Episode 2", lineName: "Owned",
            subtitles: [{name: "新字幕.srt", url: "https://example.org/episode-2.srt"}],
            danmaku: [{name: "新弹幕", url: "https://example.org/episode-2.xml"}]};
      case "/api/v1/resources/text":
        if (data.url === oldSubtitleUrl || data.url === oldDanmakuUrl) {
          return new Promise<{content: string}>((resolve, reject) => {
            pending.set(data.url!, {signal, resolve, reject});
          });
        }
        return data.url?.endsWith(".srt") ? subtitle : {content: '<i><d p="0,1,25,16777215">Owned</d></i>'};
      default:
        throw new Error("Unexpected request " + path);
    }
  });

  render(<App />);
  fireEvent.click(screen.getByRole("button", {name: /影视目录/}));
  fireEvent.change(screen.getByLabelText("订阅配置"), {target: {value: '{"sites":[]}'}});
  fireEvent.click(screen.getByRole("button", {name: "加载订阅"}));
  fireEvent.click(await screen.findByRole("button", {name: "Owned site"}));
  fireEvent.click(await screen.findByRole("button", {name: "Owned title"}));
  fireEvent.click(await screen.findByRole("button", {name: "Episode 1"}));

  fireEvent.click(await screen.findByRole("button", {name: "旧字幕.srt"}));
  fireEvent.click(screen.getByText("旧弹幕"));
  expect(pending.size).toBe(2);

  fireEvent.click(screen.getByRole("button", {name: "Episode 2"}));
  const newSubtitle = await screen.findByRole("button", {name: "新字幕.srt"});
  const cancelledOnEpisodeChange = [oldSubtitleUrl, oldDanmakuUrl].map(
    url => pending.get(url)?.signal?.aborted
  );
  fireEvent.click(newSubtitle);
  fireEvent.click(screen.getByText("新弹幕"));
  expect((await screen.findByRole("button", {name: "移除字幕"})).getAttribute("title")).toBe("新字幕.srt");
  await screen.findByText("弹幕 · 1 条");

  await act(async () => {
    pending.get(oldSubtitleUrl)?.resolve(subtitle);
    pending.get(oldDanmakuUrl)?.reject(new Error("Old episode failed"));
  });
  expect(screen.getByRole("button", {name: "移除字幕"}).getAttribute("title")).toBe("新字幕.srt");
  expect(screen.getByText("弹幕 · 1 条")).toBeTruthy();
  expect(screen.queryByText("Old episode failed")).toBeNull();
  expect(cancelledOnEpisodeChange).toEqual([true, true]);
});
