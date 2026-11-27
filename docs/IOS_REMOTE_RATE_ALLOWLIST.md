# Native iOS remote playback rate allowlist

The iPhone/iPad Control Center rate command now accepts exactly the speeds it advertises: 0.75×, 1×, 1.25×, 1.5× and 2×. This prevents stale or synthetic MPChangePlaybackRateCommandEvent values such as 1.1× from silently changing playback speed even though the option is absent from the system UI.

The same single source of truth supplies the advertised rate list and validates incoming commands. Unsupported, nonfinite and out-of-range values are rejected without changing the player's speed. The existing finite-duration VOD restriction remains; this change does not add live-stream rate controls or change the app's separate in-player speed picker.

Unit coverage: MediaLibraryTests.testRemotePlaybackRateMatchesAdvertisedOptions checks each allowed value and invalid fractional, negative, zero, out-of-range, NaN and infinite values. Final-head iPhone/iPad simulator XCTest and integration checks remain required before merge. No physical device or third-party media was used.
