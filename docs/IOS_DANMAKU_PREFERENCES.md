# Native iOS danmaku presentation preferences

P4 implementation slice: [Issue #94](https://github.com/Kahen/TV-Next/issues/94). The SwiftUI danmaku controls now restore their last locally saved values on iPhone/iPad app relaunch. The existing native overlay still uses the same parser, timeline and renderer; this change does not implement a new danmaku source or protocol.

The versioned UserDefaults key stores only enabled, opacity, font size, display area, display duration, timeline offset and comma-separated blocked words. Media URLs, subtitle/danmaku content, authentication headers, subscription addresses and account credentials are never included in this snapshot. It is device-local and is not part of the home-server library sync.

Loading rejects malformed, incomplete, oversized (over 8 KiB), non-finite and out-of-range snapshots and uses safe defaults. Saving rejects invalid values without overwriting the last good snapshot. The blocked-word field is limited to 4 KiB UTF-8. Defaults are enabled, 0.8 opacity, 22-point font, half-screen area, eight-second display, zero offset and no blocked words.

Validation: Linux-compatible Swift smoke runs positive, malformed, non-finite and size-bound cases; XCTest additionally checks all fields, corrupted payloads, isolated stores and clearing. Final-head Xcode iPhone/iPad simulator XCTest/XCUI and the complete integration gate must pass before merging. Physical-device display, external providers, native signing and formal release remain unverified.
