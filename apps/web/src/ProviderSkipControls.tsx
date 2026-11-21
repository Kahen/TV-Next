import { useEffect, useMemo, useRef, useState } from "react";
import type { RefObject } from "react";
import { normalizeProviderSkips, providerSkipTarget } from "./providerSkips";

export interface HlsSkipSource {
  url: string;
  objectURL: string;
  live: boolean | null;
}

function isSeekable(ranges: TimeRanges, time: number) {
  for (let i = 0; i < ranges.length; i++) {
    if (time >= ranges.start(i) && time <= ranges.end(i)) return true;
  }
  return false;
}

export default function ProviderSkipControls({video, segments, mediaURL, hlsSource}: {
  video: RefObject<HTMLVideoElement | null>; segments: unknown; mediaURL: string | null;
  hlsSource?: RefObject<HlsSkipSource | null>;
}) {
  const hints = useMemo(() => normalizeProviderSkips(segments), [segments]);
  const [clock, setClock] = useState({time: NaN, duration: NaN});
  const [feedback, setFeedback] = useState("");
  const [automatic, setAutomatic] = useState(false);
  // The parent keys these controls by playback generation and relay URL.
  const consumed = useRef(new Set<typeof hints[number]>());
  const awaitingSeekEnd = useRef(false);
  const pendingTarget = useRef<number | null>(null);
  const binding = useRef<{ element: HTMLVideoElement; source: string } | null>(null);

  const currentMedia = () => {
    const media = binding.current;
    if (!media || media.element !== video.current) return null;
    const {element, source} = media;
    if (element.readyState < 1 || element.error || element.seeking) return null;
    if (element.currentSrc === source) return element;
    const hls = hlsSource?.current;
    return hls?.url === source && hls.objectURL === element.currentSrc ? element : null;
  };

  useEffect(() => {
    const element = video.current;
    if (!element || !mediaURL || !hints.length) return;
    const source = new URL(mediaURL, document.baseURI).href;
    binding.current = {element, source};

    const update = (event?: Event) => {
      const media = currentMedia();
      setClock(media ? {time: media.currentTime, duration: media.duration} : {time: NaN, duration: NaN});
      if (event?.type === "emptied" || event?.type === "error") {
        pendingTarget.current = null;
        awaitingSeekEnd.current = false;
        return;
      }
      if (event?.type === "seeking") awaitingSeekEnd.current = true;
      if (event?.type === "seeked") awaitingSeekEnd.current = false;
      if (!media || awaitingSeekEnd.current) return;
      const time = media.currentTime;
      if (event?.type === "seeked") {
        const requested = pendingTarget.current;
        pendingTarget.current = null;
        if (requested === null || Math.abs(requested - time) > 0.25) {
          // Scrubbing or resuming inside a range lets the viewer watch it.
          if (automatic) {
            for (const hint of hints) {
              if (providerSkipTarget(hint, time, media.duration) !== null) consumed.current.add(hint);
            }
          }
          return;
        }
      }
      if (!automatic || pendingTarget.current !== null || media.paused || media.ended ||
          media.playbackRate <= 0 || media.readyState < 2) return;
      if (media.currentSrc !== source && hlsSource?.current?.live !== false) return;
      for (const hint of hints) {
        if (consumed.current.has(hint)) continue;
        const target = providerSkipTarget(hint, time, media.duration);
        if (target === null) continue;
        if (!isSeekable(media.seekable, target)) return;
        consumed.current.add(hint);
        pendingTarget.current = target;
        try {
          media.currentTime = target;
          setFeedback("已请求自动跳过来源标记片段。");
        } catch {
          pendingTarget.current = null;
          setFeedback("当前媒体不支持定位。");
        }
        return;
      }
    };

    const events = ["timeupdate", "playing", "loadedmetadata", "durationchange", "seeking", "seeked", "emptied", "error"];
    events.forEach(event => element.addEventListener(event, update));
    update();
    return () => {
      binding.current = null;
      events.forEach(event => element.removeEventListener(event, update));
    };
  }, [video, mediaURL, hints, hlsSource, automatic]);

  if (!hints.length) return null;
  const active = hints.find(hint => providerSkipTarget(hint, clock.time, clock.duration) !== null);
  const label = active?.type === "opening" ? "跳过来源片头" : active?.type === "middle" ? "跳过来源片段" : "跳过来源片尾";
  return <div className="player-actions" aria-label="来源片段标记">
    <span>来源片段标记：{hints.length} 个</span>
    <label><input type="checkbox" checked={automatic} disabled={!mediaURL}
      onChange={event => setAutomatic(event.target.checked)} />自动跳过本次播放的来源片段</label>
    <button disabled={!active} onClick={() => {
      const element = currentMedia();
      if (!element || !active || pendingTarget.current !== null) return;
      const target = providerSkipTarget(active, element.currentTime, element.duration);
      if (target === null) { setFeedback("播放位置已变化，请重新选择。"); return; }
      try {
        element.currentTime = target;
        consumed.current.add(active);
        setFeedback("已请求跳过来源标记片段。");
      } catch { setFeedback("当前媒体不支持定位。"); }
    }}>{active ? label : "当前不在来源标记片段内"}</button>
    {feedback && <span role="status">{feedback}</span>}
  </div>;
}
