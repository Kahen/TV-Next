# FongMi native restart/replay controls

The iPhone/iPad subscription detail provides **从本线路第一集播放** and **重播当前集**. Both invoke the existing `subscriptions/play` request and AVPlayer installation path. Restart selects the first playable episode on the currently selected line, skipping unavailable entries. Replay is enabled only after a successful episode play request and only while that episode index remains playable on the current line.

The controls are disabled during an in-flight request. Changing lines/details resets the remembered episode; replay cannot use a stale selection. Neither control loops across lines, assumes episode zero is playable, bypasses authentication, nor invokes an external Spider.

`NativeEpisodeRestartTests` covers valid first/replay selections, empty/all-unplayable lines, nil/negative/out-of-range selections and unplayable current episodes. Xcode XCTest and iPhone/iPad simulator checks remain necessary; no physical device or provider compatibility claim.
