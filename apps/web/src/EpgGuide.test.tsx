// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import EpgGuide from "./EpgGuide";
import type { Channel } from "./api";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const channel: Channel = {
  name: "News HD",
  group: "News",
  url: "https://example.org/channel.m3u8",
  tvgId: "news.hk"
};

const fakeResponse = {
  generatedAt: "2026-10-20T11:30:00Z",
  until: "2026-10-20T23:30:00Z",
  totalChannels: 1,
  matchedChannels: 1,
  channels: [{
    id: "news.hk",
    name: "News HD",
    matchedChannelId: "news.hk",
    matchType: "id",
    current: {
      start: "2026-10-20T11:00:00Z",
      stop: "2026-10-20T12:00:00Z",
      title: "Current News",
      description: null
    },
    upcoming: []
  }],
  warnings: []
};

describe("XMLTV programme guide UI", () => {
  it("does not fetch until user submits and never plays automatically", async () => {
    const fetchMock = vi.fn(async () => ({
      ok: true,
      json: async () => fakeResponse
    }));
    vi.stubGlobal("fetch", fetchMock);
    const play = vi.fn();
    render(<EpgGuide channels={[channel]} onPlay={play} />);
    expect(fetchMock).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText("XMLTV 内容"), {
      target: { value: "<tv><channel id=\"news.hk\"/></tv>" }
    });
    fireEvent.click(screen.getByRole("button", { name: "解析节目表" }));
    await waitFor(() => expect(screen.getByText("Current News")).toBeTruthy());
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [path, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(path).toBe("/api/v1/epg/guide");
    const body = JSON.parse(String(options.body));
    expect(body.channels).toEqual([{ id: "news.hk", name: "News HD" }]);
    expect(play).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "播放频道" }));
    expect(play).toHaveBeenCalledWith(channel);
  });

  it("rejects missing playlist without making an API call", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    render(<EpgGuide channels={[]} onPlay={vi.fn()} />);
    fireEvent.change(screen.getByLabelText("XMLTV 内容"), { target: { value: "<tv/>" } });
    fireEvent.click(screen.getByRole("button", { name: "解析节目表" }));
    expect(await screen.findByRole("alert")).toHaveProperty("textContent",
      "请先在“播放列表”导入含频道的 M3U，再导入相应 XMLTV。");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("shows server XML errors without displaying stale programmes", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: false,
      status: 400,
      json: async () => ({ error: "Invalid or forbidden XMLTV content" })
    })));
    render(<EpgGuide channels={[channel]} onPlay={vi.fn()} />);
    fireEvent.change(screen.getByLabelText("XMLTV 内容"), { target: { value: "<!DOCTYPE tv>" } });
    fireEvent.click(screen.getByRole("button", { name: "解析节目表" }));
    await waitFor(() => expect(screen.getByRole("alert").textContent).toContain("Invalid or forbidden XMLTV"));
    expect(screen.queryByText("Current News")).toBeNull();
  });
});
