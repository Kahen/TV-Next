# iOS FongMi opt-in automatic next episode

Native subscription details now offer **播放结束自动下一集** (off by default). When AVPlayer posts `AVPlayerItemDidPlayToEndTime` for the **exact item installed by this subscription view**, the app requests the next playable episode from the existing `subscriptions/play` endpoint and forwards the response through the same player callback.

The guard compares the notification item with both the view-owned item and the currently active AVPlayer item. Playback initiated elsewhere, stale end notifications, disabled opt-in, a busy request, the last episode, or a missing/invalid selection cannot advance. The item is invalidated before the next asynchronous request to avoid duplicate EOF requests. Changing a detail or line invalidates ownership; leaving the subscription view invalidates it too. The toggle is session-only, not persisted.

This is **not** gapless playback, prefetching, background playback policy, arbitrary provider authorization, or automatic line switching. The feature depends on PR #234's episode-navigation model. Unit tests cover next-playable selection and invalid/end boundaries; iOS notification/player integration still requires Xcode simulator CI. No remote Spider is executed.
