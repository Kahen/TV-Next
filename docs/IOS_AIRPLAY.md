# Native AirPlay route selection (P4)

TV-Next iPhone/iPad now exposes Apple's native `AVRoutePickerView` beside
the fullscreen control. Tapping it opens the system route chooser for
AirPlay-compatible destinations visible to the device. The app continues to
use the same `AVPlayer`, and explicitly leaves
`AVPlayer.allowsExternalPlayback` enabled. There is no custom-device
discovery, stored AirPlay credential or app-side network scan.

## Boundaries

- Only supported media codecs/transports and eligible AirPlay receivers can
  appear and play. HDCP/DRM or origin/relay restrictions can still prevent
  output. This does not bypass any protections.
- `AVRoutePickerView` is a system-provided UI and does not implement DLNA,
  Chromecast or arbitrary HTTP push.
- The SwiftUI external caption/danmaku overlay is not composited into the
  system's external playback feed or PiP; media with native timed tracks may
  behave differently.
- CI validates compile and the `allowsExternalPlayback` property in
  iPhone/iPad simulator. No simulator run can prove an actual AirPlay
  receiver discovery, routing, audio/video synchronization or background
  behavior. The physical-device/receiver matrix remains to be recorded
  separately. Do not close #5 until the rest of P4 is implemented.

## Device acceptance

On the same authorized network, play a known, permitted H.264/AAC MP4/HLS
fixture, tap **AirPlay 输出**, choose a real AirPlay receiver and observe
selection/return to this iPhone, seek, pause, caption limitations, and
interruption/lock behavior. Record iPhone/iPad models, iOS versions,
receiver model and exact application commit in the P4 manual acceptance
record. The route picker may show no destination when none is available.
