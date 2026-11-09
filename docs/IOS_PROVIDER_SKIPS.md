# Native provider skip segments

The supported contract follows FongMi/TV commit `123cc086159b0f13bf54bdf64bacbc259ca47c88`:

- [Result.skips](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/bean/Result.java)
- [SkipAdapter](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/gson/SkipAdapter.java)
- [SkipSegment](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/bean/SkipSegment.java)
- [VodSkipPolicy](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/playback/vod/VodSkipPolicy.java)

The original `start` and `end` are **milliseconds**, with inclusive start and exclusive end. Types are `opening`, `middle` and `ending`. An absent/null end is valid only for an ending whose start is positive; it means the remaining video. Provider order determines precedence for overlapping active segments.

## API and iPhone/iPad behavior

The existing type 3/4 subscription player response now normalizes `skips` into optional `skipSegments: [{type, startMs, endMs}]`. Pure HTTP and approved Android bridge result normalization share this path; actual ARM plugin execution remains a separate acceptance item. Numeric timestamps and bounded digit-only integer strings are accepted. Nonarrays, malformed members, negative/fractional/overflowing times, unsupported types and nonincreasing ranges are ignored without breaking playback. The API inspects at most 128 entries, retains at most 32 unique segments in provider order and caps times at seven days.

When a native subscription playback includes valid segments, **播放器 → 来源片段标记** displays a manual skip button inside the current active range. A finite ready remote media item is required. Milliseconds convert to seconds only at the AVPlayer seek boundary; an explicit end beyond the actual media duration is ineligible. Null ending end seeks to exact EOF. This does not implement automatic next-episode playback or FongMi's per-history automatic provider-skip preferences.

Receiving source metadata alone never seeks automatically. Existing manually created intro/outro markers and their explicit automatic preference remain independent. Known timeshift/live declarations, replay sessions, local files, unknown durations and stale requests cannot activate these source controls. At button invocation, the current generation, source URL, segment membership, item readiness and current range are checked again; a delayed button cannot skip a replacement episode, including one using the same URL. A retry of the same request retains its hints; an ordinary new play without metadata clears them.

Segments stay in the current in-memory playback context. They do not enter TVChannel snapshots, favorites/history, home-server sync, UserDefaults or the manual marker store. Older server responses without the new field still decode. A malformed optional array/member is ignored by the native decoder. Web UI parity remains follow-up work; native opt-in automatic behavior is described below.

The native normalization loop now stops immediately after retaining 32 unique valid entries (rather than filtering all 128 candidates first). The first 128 source entries remain the only eligible input, and original provider order and duplicate precedence are unchanged. XCTest covers invalid/duplicate entries, the 32-entry cap, and both sides of the 128-entry boundary. This is a bounded-processing improvement, not automatic skipping or new provider compatibility.

## Verification

`fixtures/fongmi-provider-skips-golden.json` anchors Kotlin normalization and native active-range/target tests, including millisecond precision, nullable endings, overlaps, exact boundaries and invalid members. Additional API tests exercise the existing subscription detail/player flow; native smoke/XCTest cover quotas and permissive optional metadata decoding. Actual AVPlayer tests verify a manual seek, no automatic seek, rejected stale/synthetic segment actions, retry, local/new-play cleanup and snapshot exclusion. Production iPhone/iPad XCUI loads an owned subscription through the normal UI, skips its opening, then selects a second episode at the same media URL and verifies the old controls disappear.

Local validation passed seven Python fixture tests, OpenAPI/fixture parsing and whitespace. [PR #175](https://github.com/Kahen/TV-Next/pull/175) source `59fff68cafe0187ee7b5ca496144100fa053a9c3` then passed [full integration](https://github.com/Kahen/TV-Next/actions/runs/41938225257) (9/9), [Web/API](https://github.com/Kahen/TV-Next/actions/runs/41938225188), [JVM integrity](https://github.com/Kahen/TV-Next/actions/runs/41938225191) and [Compose](https://github.com/Kahen/TV-Next/actions/runs/41938225149). CI verified 101 API tests with zero failures/errors/skips and 135 unit plus 31 UI tests on each iPhone/iPad simulator. The actual AVPlayer and production skip/same-URL next-episode cases passed on both platforms.

The PR merged as `d75d64612b3bfa309ae0af4c8db10343447e9a6f`; the merge tree exactly matches the tested source tree, and implementation issue #174 is closed. Owned fixtures and simulators do not replace real provider/physical-device acceptance. P2/P4 and physical acceptance #38 remain open.

## Decoder quota short-circuit (2026-11-05)

The native optional `skipSegments` decoder examines at most 128 array entries, accepts only valid distinct segments in source order, and now stops decoding additional entries immediately after retaining 32. Duplicate, malformed and invalid entries do not consume the retained quota. This is a bounded CPU/decoding improvement, not a change to seek semantics: hints remain manual and ephemeral. XCTest covers 32 valid entries, duplicates, ignored trailing entries and the 128th/129th boundary. Final-head iPhone/iPad simulator and full integration evidence must pass before merge; no physical-device or arbitrary provider compatibility is claimed.

## Opt-in automatic source skipping (2026-11-07)

`自动跳过本次播放的来源片段` is off by default. Enabling it applies the normalized opening/middle/ending ranges only to the current playback generation. It never persists metadata or consent, and new playback (including the same URL), retry, local files, revocation and clear reset consent. Pause and unknown/nonfinite media duration prevent automatic seeking. Successful automatic seeks have visible feedback.

Like the pinned upstream `VodSkipPolicy.activeSegment`, active ranges use inclusive start/exclusive end and provider order; a null ending end targets EOF. Unlike upstream's separate opening/ending history flags and always-active middle ranges, this client requires one explicit playback-local opt-in for all three kinds. There is no automatic detection or next-episode action.

The coordinator attempts each of at most 32 segments once. App seek controls suppress automatic handling of the entered range; backwards or large (>3 seconds) playhead discontinuities, including system scrubbing, suppress the entered range too. Already skipped sections can be rewatched. At 0.75–2x playback the one-second observer remains within the continuous-time budget. Off/on does not re-arm consumed segments; new playback resets the coordinator. Short ranges may be passed between observer samples, and discontinuities are conservatively treated as user seeks.

User-created automatic markers take precedence on a tick. App automatic/manual seeks share an in-flight guard and completion identity; pending seeks cannot produce multiple simultaneous automatic commands, and a stale completion cannot update a replacement item's feedback. Source automation never writes user markers or affects the existing marker preference.

Validation added: pure Swift smoke/XCTest for playing/paused states, source ordering, overlap/adjacency, milliseconds, EOF, seek/rewatch and invalid bounds; AVPlayer fixture tests for real automatic seeking, consent, pause, off/on, retry, same-URL/local cleanup and snapshot exclusion; production SwiftUI toggle/reset coverage on iPhone/iPad. These new cases require successful final-head native/full integration before merge. Physical-device/provider acceptance remains separate.

## Web manual controls (2026-11-07, pending integration)

The Web subscription player forwards normalized `skipSegments` to playback-local manual controls. It shares the JVM/Swift golden fixture, milliseconds, nullable ending-to-EOF, provider ordering and 128-inspected/32-retained bounds. Unknown duration, loading/seeking media, local files and known timeshift/replay are excluded. A click rechecks the bound video element, source and actual clock. Each playback/relay URL owns a new video element; hls.js MediaSource is supported without accepting events from an old episode. Library normalization drops hints from saved history, playlists and sync. Web automatic skipping remains unimplemented.

Validation: local Vitest tests and TypeScript/Vite production build. Browser decoding and full integration must run after push; the native automatic increment also awaits remote Xcode/simulator validation.
