# Native playback buffer diagnostics

The iPhone/iPad playback diagnostics panel reports buffered seconds **ahead of the current playback position**, not downloaded bytes or a guarantee of uninterrupted playback.

For a finite, nonnegative AVPlayerItem duration, reported lead is clamped to the remaining duration. For live/indefinite duration, the range endpoint is used. Invalid current positions, malformed ranges (negative start, reversed or nonfinite endpoints), and ranges not containing the current position are ignored. Adjacent or overlapping valid intervals are merged in time order from the playhead, while a positive gap terminates the reported continuous buffer. The scan is restricted to the first 32 supplied ranges before sorting and merging. The existing 32-range scan and 24-hour display bound remain. A missing applicable range displays “未报告”; a valid range ending exactly at the current position displays zero seconds.

## Automated acceptance

`NativePlaybackDiagnosticsTests` covers finite-duration clamping, indefinite duration, overlapping and adjacent out-of-order ranges, positive gaps, malformed intervals, 32-range truncation, negative/nonfinite positions, malformed ranges, outside-range positions and the exact media endpoint. The existing owned MP4/AAC/PCM and redacted-error tests remain.

Required before merge: final-head iPhone and iPad simulator XCTest, standalone Web/API CI and full cross-platform integration gate. This does **not** establish physical-device decoder/buffering performance or real-provider compatibility. No remote plugins, external media or signing artifacts are added.
