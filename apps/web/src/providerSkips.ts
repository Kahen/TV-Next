export interface ProviderSkipSegment {
  type: "opening" | "middle" | "ending";
  startMs: number;
  endMs: number | null;
}

/** Mirrors the normalized API/Swift contract, not the upstream raw skips JSON. */
export function normalizeProviderSkips(input: unknown): ProviderSkipSegment[] {
  if (!Array.isArray(input)) return [];
  const result: ProviderSkipSegment[] = [];
  const seen = new Set<string>();
  for (const entry of input.slice(0, 128)) {
    if (!entry || typeof entry !== "object") continue;
    const {type, startMs, endMs} = entry;
    if (!["opening", "middle", "ending"].includes(type) || !Number.isSafeInteger(startMs) || startMs < 0 || startMs > 604800000) continue;
    if (endMs == null ? type !== "ending" || startMs === 0
      : !Number.isSafeInteger(endMs) || endMs <= startMs || endMs > 604800000) continue;
    const segment: ProviderSkipSegment = {type, startMs, endMs: endMs ?? null};
    const key = JSON.stringify(segment);
    if (seen.has(key)) continue;
    seen.add(key); result.push(segment);
    if (result.length === 32) break;
  }
  return result;
}

export function providerSkipTarget(segment: ProviderSkipSegment, current: number, duration: number): number | null {
  if (!Number.isFinite(current) || !Number.isFinite(duration) || duration <= 0 || duration >= 604800 || current < 0 || current >= duration) return null;
  const start = segment.startMs / 1000;
  const end = segment.endMs == null ? duration : segment.endMs / 1000;
  return start < duration && end <= duration && current >= start && current < end ? end : null;
}
