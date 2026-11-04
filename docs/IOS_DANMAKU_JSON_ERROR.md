# Native danmaku JSON failure taxonomy

Malformed JSON inputs now map `JSONSerialization` decoding failures to the same `DanmakuError.invalid` used for invalid XML and unsupported JSON shapes. This avoids leaking platform-specific `NSError` details through the native SwiftUI error surface. Valid dandanplay-style JSON and XML parsing behavior remain unchanged.

Regression: `cd apps/ios && swiftc -warnings-as-errors TVNext/DanmakuParser.swift tests/DanmakuSmoke.swift -o /tmp/tvnext-danmaku-tests && /tmp/tvnext-danmaku-tests`. The smoke covers valid XML/JSON and three malformed JSON variants. This does not authorize remote providers, expand the Spider sandbox, or establish physical-device compatibility. Final PR HEAD iPhone/iPad simulator and aggregate CI are required before merge.
