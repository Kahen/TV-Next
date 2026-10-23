import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { scheduleDanmaku } from "./danmaku";
import type { DanmakuComment } from "./danmaku";
export interface DanmakuSettings { enabled: boolean; opacity: number; fontSize: number; area: number; duration: number; offset: number; blocked: string }
export const defaultDanmakuSettings: DanmakuSettings = { enabled: true, opacity: 0.8, fontSize: 24, area: 0.5, duration: 8, offset: 0, blocked: "" };
export default function DanmakuOverlay({ video, comments, settings }: { video: RefObject<HTMLVideoElement | null>; comments: DanmakuComment[]; settings: DanmakuSettings }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const surface = canvas.current, media = video.current;
    if (!surface || !media) return;
    const ctx = surface.getContext("2d");
    if (!ctx) return;
    if (!settings.enabled || !comments.length) { ctx.clearRect(0,0,surface.width,surface.height); return; }
    let frame = 0, width = 0, height = 0;
    let schedule: ReturnType<typeof scheduleDanmaku> = [];
    const observer = new ResizeObserver(() => {
      width = surface.clientWidth; height = surface.clientHeight;
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      surface.width = width * ratio; surface.height = height * ratio;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      ctx.font = `${settings.fontSize}px sans-serif`;
      const blocked = settings.blocked.split(/[,，\n]/).map(s => s.trim()).filter(Boolean);
      schedule = scheduleDanmaku(comments.filter(c => !blocked.some(word => c.text.includes(word))), width,
        Math.max(1, Math.floor(height * settings.area / (settings.fontSize + 8))), settings.duration, text => ctx.measureText(text).width);
      draw();
    });
    observer.observe(surface);
    const draw = () => {
      cancelAnimationFrame(frame);
      ctx.clearRect(0, 0, width, height);
      const now = media.currentTime - settings.offset;
      if (settings.enabled && Number.isFinite(now)) {
        ctx.font = `${settings.fontSize}px sans-serif`; ctx.globalAlpha = settings.opacity;
        ctx.textBaseline = "top"; ctx.lineWidth = 3; ctx.strokeStyle = "#000";
        // Binary upper bound avoids walking future comments on every animation frame.
        let low = 0, high = schedule.length;
        while (low < high) { const mid = (low + high) >>> 1; if (schedule[mid].time <= now) low = mid + 1; else high = mid; }
        for (let i = low - 1; i >= 0 && schedule[i].time > now - settings.duration; i--) {
          const c = schedule[i], progress = (now - c.time) / settings.duration;
          const x = c.mode === 4 || c.mode === 5 ? (width - c.width) / 2 : c.mode === 6 ? -c.width + progress * (width + c.width) : width - progress * (width + c.width);
          const y = c.mode === 4 ? height - (c.lane + 1) * (settings.fontSize + 8) : c.lane * (settings.fontSize + 8);
          ctx.strokeStyle = c.color === "#000000" ? "#fff" : "#000";
          ctx.fillStyle = c.color; ctx.strokeText(c.text, x, y); ctx.fillText(c.text, x, y);
        }
      }
      if (!media.paused && !media.ended) frame = requestAnimationFrame(draw);
    };
    for (const event of ["play","pause","seeked","timeupdate"]) media.addEventListener(event,draw);
    frame = requestAnimationFrame(draw);
    return () => { for (const event of ["play","pause","seeked","timeupdate"]) media.removeEventListener(event,draw); cancelAnimationFrame(frame); observer.disconnect(); ctx.clearRect(0, 0, width, height); };
  }, [video, comments, settings]);
  return <canvas ref={canvas} className="danmaku-overlay" aria-hidden="true"/>;
}
