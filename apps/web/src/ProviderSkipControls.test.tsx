// @vitest-environment jsdom
import { afterEach, expect, it } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import ProviderSkipControls from "./ProviderSkipControls";

afterEach(cleanup);
const url = "https://example.org/owned.mp4";
const segments = [{type: "opening", startMs: 0, endMs: 15250}];
function videoFixture() {
  const current = document.createElement("video");
  Object.defineProperties(current, {
    currentSrc: {value: url, configurable: true},
    readyState: {value: 1, configurable: true},
    duration: {value: 120, configurable: true}
  });
  return {current};
}
it("requires a manual click, uses milliseconds, and resets same-URL episode feedback", () => {
  const video = videoFixture();
  const view = render(<ProviderSkipControls key={1} video={video} mediaURL={url} segments={segments}/>);
  expect(video.current.currentTime).toBe(0);
  fireEvent.click(screen.getByRole("button", {name: "跳过来源片头"}));
  expect(video.current.currentTime).toBe(15.25);
  expect(screen.getByRole("status").textContent).toContain("已请求跳过");
  view.rerender(<ProviderSkipControls key={2} video={video} mediaURL={url} segments={[]}/>);
  expect(screen.queryByRole("button")).toBeNull();
  expect(screen.queryByRole("status")).toBeNull();
  fireEvent.timeUpdate(video.current);
  expect(screen.queryByRole("button")).toBeNull();
});
it("rechecks the actual clock and media identity at click time", () => {
  const video = videoFixture();
  render(<ProviderSkipControls video={video} mediaURL={url} segments={segments}/>);
  const button = screen.getByRole("button", {name: "跳过来源片头"});
  video.current.currentTime = 40; // no timeupdate: deliberately stale rendered button
  fireEvent.click(button);
  expect(video.current.currentTime).toBe(40);
  video.current.currentTime = 1;
  Object.defineProperty(video.current, "currentSrc", {value: "https://example.org/next.mp4"});
  fireEvent.click(button);
  expect(video.current.currentTime).toBe(1);
});
it("disables unknown-duration and loading media", () => {
  const video = videoFixture();
  Object.defineProperty(video.current, "duration", {value: Infinity});
  render(<ProviderSkipControls video={video} mediaURL={url} segments={segments}/>);
  expect((screen.getByRole("button") as HTMLButtonElement).disabled).toBe(true);
});
it("allows hls.js MediaSource only on its bound playback element", () => {
  const video = videoFixture();
  const objectURL = "blob:https://example.org/owned-media-source";
  Object.defineProperty(video.current, "currentSrc", {value: objectURL});
  const hls = {current: {url, objectURL, live: false}};
  render(<ProviderSkipControls video={video} mediaURL={url} segments={segments} hlsSource={hls}/>);
  const button = screen.getByRole("button", {name: "跳过来源片头"});
  fireEvent.click(button);
  expect(video.current.currentTime).toBe(15.25);
  const replacement = videoFixture().current;
  video.current = replacement;
  fireEvent.click(button);
  expect(replacement.currentTime).toBe(0);
});

function playableVideo() {
  const video = videoFixture();
  Object.defineProperties(video.current, {
    readyState: {value: 4, configurable: true},
    paused: {value: false, configurable: true},
    seekable: {value: {length: 1, start: () => 0, end: () => 120}, configurable: true}
  });
  return video;
}

it("requires opt-in for each episode and only advances once per marked range", () => {
  const video = playableVideo();
  const hints = [...segments, {type: "middle", startMs: 15250, endMs: 24000}];
  const view = render(<ProviderSkipControls key={1} video={video} mediaURL={url} segments={hints}/>);
  const toggle = screen.getByRole("checkbox") as HTMLInputElement;
  expect(toggle.checked).toBe(false);
  fireEvent.timeUpdate(video.current);
  expect(video.current.currentTime).toBe(0);
  fireEvent.click(toggle);
  expect(video.current.currentTime).toBe(15.25);
  fireEvent.timeUpdate(video.current); // still awaiting seek completion
  expect(video.current.currentTime).toBe(15.25);
  fireEvent.seeked(video.current);
  expect(video.current.currentTime).toBe(24);
  fireEvent.seeked(video.current);
  video.current.currentTime = 1;
  fireEvent.seeking(video.current);
  fireEvent.seeked(video.current);
  fireEvent.click(toggle);
  fireEvent.click(toggle);
  fireEvent.timeUpdate(video.current);
  expect(video.current.currentTime).toBe(1);
  view.rerender(<ProviderSkipControls key={2} video={video} mediaURL={url} segments={hints}/>);
  expect((screen.getByRole("checkbox") as HTMLInputElement).checked).toBe(false);
});

it("respects user scrubbing into a new segment, even with timeupdate before seeked", () => {
  const video = playableVideo();
  const hints = [{type: "ending", startMs: 90000, endMs: null}];
  render(<ProviderSkipControls video={video} mediaURL={url} segments={hints}/>);
  fireEvent.click(screen.getByRole("checkbox"));
  video.current.currentTime = 100;
  fireEvent.seeking(video.current);
  fireEvent.timeUpdate(video.current);
  fireEvent.seeked(video.current);
  fireEvent.timeUpdate(video.current);
  expect(video.current.currentTime).toBe(100);
});

it("waits for playing and seekable VOD before skipping through EOF", () => {
  const video = playableVideo();
  video.current.currentTime = 100;
  Object.defineProperty(video.current, "paused", {value: true});
  render(<ProviderSkipControls video={video} mediaURL={url}
    segments={[{type: "ending", startMs: 95000, endMs: null}]}/>);
  fireEvent.click(screen.getByRole("checkbox"));
  expect(video.current.currentTime).toBe(100);
  Object.defineProperties(video.current, {
    paused: {value: false}, seekable: {value: {length: 1, start: () => 0, end: () => 105}}
  });
  fireEvent.playing(video.current);
  expect(video.current.currentTime).toBe(100);
  Object.defineProperty(video.current, "seekable", {value: {length: 1, start: () => 0, end: () => 120}});
  fireEvent.timeUpdate(video.current);
  expect(video.current.currentTime).toBe(120);
});

it("ignores live HLS and blobs belonging to a previous attachment", () => {
  const video = playableVideo();
  const hls = {current: {url, objectURL: "blob:https://example.org/current", live: true}};
  Object.defineProperty(video.current, "currentSrc", {value: hls.current.objectURL});
  render(<ProviderSkipControls video={video} mediaURL={url} segments={segments} hlsSource={hls}/>);
  fireEvent.click(screen.getByRole("checkbox"));
  expect(video.current.currentTime).toBe(0);
  hls.current.live = false;
  Object.defineProperty(video.current, "currentSrc", {value: "blob:https://example.org/replaced"});
  fireEvent.timeUpdate(video.current);
  expect(video.current.currentTime).toBe(0);
  Object.defineProperty(video.current, "currentSrc", {value: hls.current.objectURL});
  fireEvent.timeUpdate(video.current);
  expect(video.current.currentTime).toBe(15.25);
});
