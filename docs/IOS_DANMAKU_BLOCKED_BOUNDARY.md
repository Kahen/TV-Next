# Native danmaku blocked-word truncation

The device-local danmaku blocked-word preference is capped at 4,096 UTF-8 bytes. The editable text is truncated at a complete Swift `Character` (extended grapheme-cluster) boundary, not at an individual Unicode scalar. This avoids persisting an incomplete combining-character sequence or emoji ZWJ sequence when the field exceeds the limit. Existing text within the limit is unchanged; no remote comment data or media URLs are persisted by this preference.

## Verification

Run from `apps/ios`:

```sh
swiftc -warnings-as-errors TVNext/DanmakuOptions.swift tests/DanmakuOptionsSmoke.swift -o /tmp/tvnext-danmaku-options-tests
/tmp/tvnext-danmaku-options-tests
```

Regression cases include normal multilingual text, exact 4,096-byte fit, a combining-mark boundary, an emoji-family sequence, and previously existing invalid preference rejection. The iPhone and iPad simulator workflows and complete integration gate must pass at the final PR HEAD before merging. No physical-device compatibility or external-source test is claimed.
