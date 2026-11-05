# Native provider skip segments

The supported contract follows FongMi/TV commit `123cc086159b0f13bf54bdf64bacbc259ca47c88`:

- [Result.skips](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/bean/Result.java)
- [SkipAdapter](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/gson/SkipAdapter.java)
- [SkipSegment](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/bean/SkipSegment.java)
- [VodSkipPolicy](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/playback/vod/VodSkipPolicy.java)

The original `start` and `end` are **milliseconds**, with inclusive start and exclusive end. Types are `opening`, `middle` and `ending`. An absent/null end is valid only for an ending whose start is positive; it means the remaining video. Provider order determines precedence for overlapping active segments.

## API and iPhone/iPad behavior

The existing type 3/4 subscription player response now normalizes `skips` into optional `skipSegments: [{type, startMs, endMs}]`. Pure HTTP and approved Android bridge result normalization share this path; actual ARM plugin execution remains a separate acceptance item. Numeric timestamps and bounded digit-only integer strings are accepted. Nonarrays, malformed members, negative/fractional/overflowing times, unsupported types and nonincreasing ranges are ignored without breaking playback. The API inspects at most 128 entries, retains at most 32 unique segments in provider order and caps times at seven days.

When a native subscription playback includes valid segments, **播放器 → 来源片段标记** displays a manual skip button inside the current active range. A finite ready remote media item is required. Milliseconds convert to seconds only at the AVPlayer seek boundary; an explicit end beyond the actual media duration is ineligible. Null ending end seeks to exact EOF. This does not implement automatic next-episode playback or FongMi's per-history automatic provider-skip policy.

Receiving source metadata never seeks automatically. Existing manually created intro/outro markers and their explicit automatic preference remain independent. Known timeshift/live declarations, replay sessions, local files, unknown durations and stale requests cannot activate these source controls. At button invocation, the current generation, source URL, segment membership, item readiness and current range are checked again; a delayed button cannot skip a replacement episode, including one using the same URL. A retry of the same request retains its hints; an ordinary new play without metadata clears them.

Segments stay in the current in-memory playback context. They do not enter TVChannel snapshots, favorites/history, home-server sync, UserDefaults or the manual marker store. Older server responses without the new field still decode. A malformed optional array/member is ignored by the native decoder. Web UI parity and provider-driven automatic skipping remain follow-up work.

## Verification

`fixtures/fongmi-provider-skips-golden.json` anchors Kotlin normalization and native active-range/target tests, including millisecond precision, nullable endings, overlaps, exact boundaries and invalid members. Additional API tests exercise the existing subscription detail/player flow; native smoke/XCTest cover quotas and permissive optional metadata decoding. Actual AVPlayer tests verify a manual seek, no automatic seek, rejected stale/synthetic segment actions, retry, local/new-play cleanup and snapshot exclusion. Production iPhone/iPad XCUI loads an owned subscription through the normal UI, skips its opening, then selects a second episode at the same media URL and verifies the old controls disappear.

Local validation covers Python fixture tests, OpenAPI/fixture parsing and whitespace. This Linux session has Java 17 and no Swift/Xcode; Java 21/Gradle and native verification must pass in final-head CI before merge. Owned fixtures and simulators do not replace real provider/physical-device acceptance. P2/P4 remain open.
