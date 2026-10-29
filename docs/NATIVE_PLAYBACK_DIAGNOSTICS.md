# Native playback diagnostics

Expand **播放器 → 播放诊断** to inspect AVPlayer state, position/duration,
reported buffered lead, video/audio codec identifiers, dimensions, audio sample
rate/channel count and a sanitized error code. Timeline fields refresh while the
panel is open; metadata also has an explicit Refresh action. Item identity and
request generation prevent late metadata loads from replacing a newer selection.
The panel is read-only and does not replace, seek or cancel the playing AVAsset.

Only bounded numeric/codec fields are extracted. Raw URLs, signed query strings,
headers, NSError descriptions/userInfo and access/error log events are neither
displayed nor persisted. Unknown error domains are replaced by `PlayerError`.
Codec identifiers describe the encoded stream. AVFoundation does not expose the
actual selected hardware decoder, and this UI makes no hardware-decoding claim.
Unready/indefinite sources show unknown values; metadata errors preserve playback.

XCTest reads the owned H.264 fixture's actual 160×90 format description, a generated
48 kHz stereo PCM audio file's format, and checks
empty-player state, finite-time handling and secret-bearing error redaction.
Production XCUI opens and refreshes the panel without media on both device families.
Final-head iPhone/iPad simulator and full integration gates are required. Device
codec/energy/unsupported-media behavior remains separate physical acceptance.
