# Native M3U single-quoted metadata

The offline iOS M3U parser accepts `#EXTINF` attributes enclosed in single or double quotes, including commas in `group-title`. Attribute values remain bounded by the existing channel name/group/logo/tvg-id limits; stream URLs continue to require credential-free HTTP(S). Missing comma titles still fall back to `tvg-name` or `Unnamed`. Mixed or malformed quote pairs are not interpreted as valid quoted attributes.

Regression coverage: `apps/ios/tests/ParserSmoke.swift` includes both quote styles, a comma inside a group, title fallback, logo/tvg-id, and a rejected JavaScript media address. Run the existing iOS parser smoke in `.github/workflows/ios.yml`. Xcode simulator and full integration checks are required before merging; this change does not claim compatibility with real third-party subscriptions.
