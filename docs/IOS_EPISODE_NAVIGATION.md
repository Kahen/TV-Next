# Native subscription episode navigation

The iPhone/iPad subscription detail now exposes Previous/Next episode actions. They become enabled only after a successful playback request. Navigation remains on the currently selected line and skips episodes marked non-playable, preserving original server episode indices. Changing line, detail, subscription or server invalidates the previous episode selection. The buttons request playback through the existing `subscriptions/play` endpoint and do not attempt automatic playback when AVPlayer finishes.

Run the standalone production-source regression with:

```sh
swiftc apps/ios/TVNext/NativeEpisodeNavigation.swift scripts/NativeEpisodeNavigationSmoke.swift -o /tmp/tvnext-episode-navigation
/tmp/tvnext-episode-navigation
```

This checks nine positive and negative cases. Full iOS UI and simulator tests require Xcode. The standalone test does not validate the SwiftUI build or remote playback.
