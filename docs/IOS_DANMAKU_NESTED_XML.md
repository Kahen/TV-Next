# Native XML danmaku nested-element ownership

The XML parser binds an active `<d>` to its opening depth. A nested `<d>` is treated as text within the outer comment, not a second comment or a replacement for its `p` metadata. Only the matching closing depth completes that comment; following siblings parse normally. This is defensive behavior for malformed/unusual feeds, not an assertion that nested comments are part of the upstream FongMi schema.

Regression: `cd apps/ios && swiftc -warnings-as-errors TVNext/DanmakuParser.swift tests/DanmakuSmoke.swift -o /tmp/tvnext-danmaku-smoke && /tmp/tvnext-danmaku-smoke`. The smoke checks ordinary XML/JSON, forbidden DTD, nested ownership and following siblings. Full iPhone/iPad simulator and aggregate CI on the final PR HEAD remain required before merge. No real-provider, device, security audit or release evidence is claimed.
