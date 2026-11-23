# Native FongMi episode playback title

The iPhone/iPad subscription detail view now captures the selected playable episode and line before requesting `subscriptions/play`. The player receives a bounded series + episode display label rather than only the series name. This improves Now Playing and playback identification without persisting provider URLs.

Requests for out-of-range or non-playable episodes are rejected before network dispatch. Responses are discarded if the active line changes before completion; the existing generation cancellation remains in effect.

`NativeFongMiEpisodeTitle` removes Unicode control/format/line separators, suppresses HTTP(S) URL-shaped labels, and bounds each component to 120 characters. It is a metadata display helper, not a URL sanitizer or authorization mechanism.

Tests: `NativeFongMiEpisodeTitleTests` covers valid Unicode, duplicate/blank labels, URL/control rejection and length bounds. iOS Xcode build and simulator tests must still run on macOS. No provider or device compatibility is claimed.
