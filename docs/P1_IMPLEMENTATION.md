# P1 implementation and automated acceptance

Updated 2026-10-25. Implementation is tracked in [#2](https://github.com/Kahen/TV-Next/issues/2) and [PR #37](https://github.com/Kahen/TV-Next/pull/37). At the user's explicit request, physical-device acceptance is tracked separately in [#38](https://github.com/Kahen/TV-Next/issues/38). A closed implementation issue does not imply physical-device, signed-release or full TVBox compatibility acceptance.

## Task-to-evidence map

| P1 task | Implementation | Automated verification |
| --- | --- | --- |
| Persistent playlists, favorites, history and finite-VOD resume | Bounded Web localStorage and native UserDefaults; private headers removed, local file URLs excluded; explicit clear | Web library tests and real-browser reload/resume; native store persistence/redaction/clear tests and SwiftUI relaunch |
| M3U and static JSON file/paste import | Web/API and local Swift parsers; original shared golden fixtures; native Files pickers and export | Kotlin/Swift/Web shared parser contracts; browser file upload and API integration; SwiftUI paste/import and JSON error recovery |
| Groups, search, empty/error states and subtitle basics | Both clients; SRT/VTT text cues/offset; failed imports preserve library; item-scoped native failure/retry | Browser MP4/HLS/local/caption/error recovery; SwiftUI favorite/recent/search/invalid-import tests; caption smoke and real AVPlayer unit tests |
| Playback speed, fullscreen, orientation and available PiP | Web native browser APIs with failure feedback; native 0.75–2× AVPlayer, explicit fullscreen retaining overlays and standard AVKit PiP controls where supported; portrait/landscape and iPad multitasking supported by layout/config | Browser speed and viewport tests; native speed bounds, fullscreen/rotation/background-return UI tests on iPhone and iPad simulators |
| Keyboard/touch/accessibility and lifecycle | Web skip link, active states, focusable file inputs; native labeled controls, 44-point favorite targets, section navigation and large-text menu controls; synchronous Web pagehide save; native background save/pause | Chromium/Firefox/WebKit keyboard/narrow viewport/pagehide regressions; both simulator families exercise production SwiftUI at accessibility Dynamic Type |
| Integration, PWA and published limits | Full cross-platform gate; deterministic PNG install icons; shell-only service worker; CORS/codec restrictions documented | Three browser engines decode owned synthetic MP4/HLS; offline shell reload checks exclude API/media cache; XCTest plus UI tests and unsigned simulator build |

P1 supports user-initiated system PiP through AVPlayerViewController with its audio/background configuration, restoration delegate and interruption handling. Ordinary backgrounding pauses; an explicit PiP transition retains playback. Pending relay creation is invalidated in either case. General background-media controls remain P4 work (#5). Browser PiP/fullscreen availability depends on the engine and user gesture; unavailable operations report a message. No unsupported browser or device API is represented as implemented.

## Reproduce

Web: run `npm ci`, `npm test` and `npm run build` in `apps/web`. Run `npm run test:e2e` against the production Compose/nginx service as described in [BROWSER_ACCEPTANCE.md](BROWSER_ACCEPTANCE.md). The test-owned FFmpeg fixture server generates video locally; no third-party streaming service or subscription is required.

Native: use macOS/Xcode and XcodeGen. Generate the synthetic video with `python3 scripts/browser_media_fixture.py`, copy `http://127.0.0.1:8765/fixture.mp4` to `apps/ios/tests/unit/Fixtures/fixture.mp4`, keep the fixture server running, then run `xcodegen generate` in `apps/ios`. Use `xcodebuild -project TVNext.xcodeproj -scheme TVNext -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' CODE_SIGNING_ALLOWED=NO test` for an available iPhone and iPad. CI selects both families and fails when either is missing; it does not silently skip unavailable UI tests. Test bundles and the fixture server are never included in the application target. `native-iPhone-simulator-acceptance` and `native-iPad-simulator-acceptance` retain xcresult bundles for failures and successes.

Unit tests use isolated UserDefaults suites. UI tests enter data through production controls and relaunch the application; there are no seeded libraries, test-only routes or bypassed player/network results. Codec fixtures use synthetic H.264 baseline MP4/HLS. This does not validate arbitrary codecs, third-party Files providers, VoiceOver behavior, installed-PWA update prompts, interruptions, energy use or iPad Split View on physical hardware; those are listed in #38.

## Release boundary

Physical iPhone/iPad playback, accessibility assistive-technology review and installed-PWA acceptance remain pending in #38. Advanced background media/AirPlay, styled ASS, embedded tracks, transcoding, real Spider execution and direct cloud account login remain in P2–P6. No signed IPA or App Store approval is claimed.
