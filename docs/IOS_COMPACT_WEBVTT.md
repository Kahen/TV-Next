# Compact WebVTT header compatibility (native iOS)

The native caption parser accepts a WebVTT cue immediately after the `WEBVTT` header even if the exporter omits the usual blank separator. An optional header title (`WEBVTT - exported`) and an optional cue identifier are also supported. A header without any timed cue still fails with `CaptionError.invalidTimeline`.

This only changes the existing local/WebDAV caption text parser; it does not fetch additional URLs, execute WebVTT content, alter subtitle size limits (1 MiB), or enable untrusted scripts.

Regression cases are in `apps/ios/tests/CaptionSmoke.swift`. Run the Swift smoke target and iOS simulator checks when the Xcode environment is available. Physical-device compatibility is not asserted.
