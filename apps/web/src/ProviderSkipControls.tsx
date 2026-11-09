import { useEffect, useMemo, useRef, useState } from "react";
import type { RefObject } from "react";
import { normalizeProviderSkips, providerSkipTarget } from "./providerSkips";

export default function ProviderSkipControls({video, segments, mediaURL}: {
  video: RefObject<HTMLVideoElement | null>; segments: unknown; mediaURL: string | null;
}) {
  const hints = useMemo(() => normalizeProviderSkips(segments), [segments]);
  const [clock, setClock] = useState({time: NaN, duration: NaN});
  const [feedback, setFeedback] = useState("");
  const binding = useRef<{ element: HTMLVideoElement; source: string } | null>(null);

  const currentMedia = () => {
    const media = binding.current;
    if (!media || media.element !== video.current) return null;
    const {element, source} = media;
    if (element.readyState < 1 || element.error || element.seeking) return null;
    // The player attaches hls.js MediaSource to this playback's own element.
    return element.currentSrc === source || element.currentSrc.startsWith("blob:") ? element : null;
  };

  useEffect(() => {
    const element = video.current;
    if (!element || !mediaURL || !hints.length) return;
    const source = new URL(mediaURL, document.baseURI).href;
    binding.current = {element, source};
    const update = () => {
      const media = currentMedia();
      setClock(media ? {time: media.currentTime, duration: media.duration} : {time: NaN, duration: NaN});
    };
    const events = ["timeupdate", "loadedmetadata", "durationchange", "seeking", "seeked", "emptied", "error"];
    events.forEach(event => element.addEventListener(event, update));
    update();
    return () => {
      binding.current = null;
      events.forEach(event => element.removeEventListener(event, update));
    };
  }, [video, mediaURL, hints.length]);
  if (!hints.length) return null;
  const active = hints.find(hint => providerSkipTarget(hint, clock.time, clock.duration) !== null);
  const label = active?.type === "opening" ? "跳过来源片头" : active?.type === "middle" ? "跳过来源片段" : "跳过来源片尾";
  return <div className="player-actions" aria-label="来源片段标记">
    <span>来源片段标记：{hints.length} 个</span>
    <button disabled={!active} onClick={() => {
      const element = currentMedia();
      if (!element || !active) return;
      const target = providerSkipTarget(active, element.currentTime, element.duration);
      if (target === null) { setFeedback("播放位置已变化，请重新选择。"); return; }
      try { element.currentTime = target; setFeedback("已请求跳过来源标记片段。"); }
      catch { setFeedback("当前媒体不支持定位。"); }
    }}>{active ? label : "当前不在来源标记片段内"}</button>
    <small>来源标记仅用于本次播放，点击后跳过。</small>
    {feedback && <span role="status">{feedback}</span>}
  </div>;
}
