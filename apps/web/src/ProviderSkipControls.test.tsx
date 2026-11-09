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
  Object.defineProperty(video.current, "currentSrc", {value: "blob:https://example.org/owned-media-source"});
  render(<ProviderSkipControls video={video} mediaURL={url} segments={segments}/>);
  const button = screen.getByRole("button", {name: "跳过来源片头"});
  fireEvent.click(button);
  expect(video.current.currentTime).toBe(15.25);
  const replacement = videoFixture().current;
  video.current = replacement;
  fireEvent.click(button);
  expect(replacement.currentTime).toBe(0);
});
