# iOS offline JSON configuration preview (P1)

The iOS/iPadOS 17+ application now has a local FongMi JSON preview panel. Paste a JSON object or choose a JSON document from Files, then select "检查 JSON 配置".

Supported metadata: site key/name/type, searchable/hidden declarations, category names, live-source count and presence of a Spider declaration. The parser does not execute plugins, fetch remote URLs, connect to media providers, import playlists or persist configuration.

Limits: 1,048,576 UTF-8 bytes per file or pasted value; JSON root must be an object; optional sites/lives must be arrays. At most 1000 sites are shown; duplicate/empty keys are skipped. Names/keys are capped at 200 characters, categories at 50 entries of 100 characters. Warnings are displayed for more than 1000 sites or 50 live declarations. The preview is discarded when input changes or parsing fails.

Test locally on a Mac with Swift installed, from apps/ios:

```sh
swiftc TVNext/OfflineConfigPreview.swift tests/ConfigSmoke.swift -o /tmp/tvnext-config-tests
/tmp/tvnext-config-tests
```

GitHub Actions also builds the unsigned iOS Simulator target. This does not verify Files providers, VoiceOver, playback or browser parity on physical devices. See docs/ACCEPTANCE.md and Issue #2. No IPA, TestFlight or App Store distribution is included.
