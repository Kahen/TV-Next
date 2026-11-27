# iOS FongMi episode filter

Native subscription detail now offers a local, per-line episode name filter. It uses case/diacritic-insensitive substring matching and ignores leading/trailing query whitespace. Switching playback lines or loading a different detail resets the query.

**Playback identity:** Filter results retain the original zero-based episode indices from the provider response. Selecting a filtered item calls the existing `subscriptions/play` endpoint with the original `lineIndex` and `episodeIndex`, never the filtered list offset. Duplicate names remain separate episodes. Non-playable entries remain disabled.

This is display-only filtering of already loaded episode metadata, not a server-side search or a claim of provider/codec compatibility. It does not execute Spider code or persist user queries.

Regression coverage: `NativeEpisodeFilterTests` includes empty/whitespace query, Unicode, case/diacritic matching, duplicate titles, no-match/empty-line and noncontiguous original indices. Run iPhone/iPad XCTest and full integration on the PR head before merge; physical-device acceptance is deferred.
