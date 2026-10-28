# Native background audio and system media controls

This increment maps the background/session transport behavior of original
[FongMi PlaybackService](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/service/PlaybackService.java)
to native iOS APIs. It is not an Android service port or full Media3 parity.

The player has an explicit **后台继续播放音频** toggle, off by default. When
enabled, an already installed AVPlayerItem may continue its audio after app
backgrounding or screen lock. The existing `audio` background mode and playback
audio session are used with `audiovisualBackgroundPlaybackPolicy = .continuesIfPossible`.
Non-PiP AVPlayerViewController surfaces detach their player while backgrounded
and reconnect on return; explicit PiP keeps its presentation attached. This
follows Apple's [background playback guidance](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MediaPlaybackGuide/Contents/Resources/en.lproj/RefiningTheUserExperience/RefiningTheUserExperience.html)
and [AVPlayer background policy](https://developer.apple.com/documentation/avfoundation/avplayeraudiovisualbackgroundplaybackpolicy).

The toggle stores one device-local boolean. It does not enter library/account
sync and is deleted by clear-library. Backgrounding still invalidates pending
relay/replay operations, so a late network response cannot start a new item.
Disabling the toggle while backgrounded pauses non-PiP audio. Interruptions and
headphone removal always pause; this increment never automatically resumes
after them. Returning to the foreground also does not automatically resume.

## System transport and metadata

`MPRemoteCommandCenter` handles play, pause, toggle, stop-as-pause, finite-VOD
seek, 15-second backward/forward skip and bounded 0.75–2x VOD speed. Missing/failed items, unavailable
playback, NaN/infinite/out-of-range seeks and invalid skip intervals fail without
changing the selected media. Live/unknown-duration media do not advertise seek.
Playback speed is retained when resuming, and system rate changes update the production picker. Command validation runs on
the main actor even if the system invokes the handler on another thread.

`MPNowPlayingInfoCenter` publishes bounded title/local filename, elapsed time,
duration when known, live flag and current/default rate. It does not receive
media URLs, local file URLs, cookies, headers, relay capabilities or account
tokens. URL-shaped titles are replaced with a generic label; artwork is not
fetched. A single active controls owner prevents old stores/timers from replacing
the current player's metadata or clearing another store's commands. Clearing
the active library removes its command targets and Now Playing metadata.

Apple's MPNowPlayingSession is deliberately not combined with this app's
AVPlayerViewController. The app owns its Now Playing info and the AVKit
controller's automatic metadata publishing remains disabled.

## Native inline 15-second seek controls

The SwiftUI player now offers explicit **后退 15 秒** and **前进 15 秒**
buttons alongside its playback speed menu. These actions call the same
`MediaLibraryStore.handleSystemPlaybackCommand(.skip)` path as the system
remote controls: a seek is bounded to 0…duration, rejected for unknown/live
duration or failed/unready items, and does not replace the current player item.
Buttons are disabled when no player item exists; when a loaded item cannot
seek, the UI shows a non-sensitive explanatory message. New playback clears
that message. This is manual seeking, **not** automatic intro/outro detection
or chapter-marker support.

## Verification boundaries

XCTest uses the owned local media fixture to exercise default-off pause, opt-in
retention, stored preference, interruption pause, explicit resume, seek/rate/
toggle validation, clear-data cleanup and competing metadata ownership. Existing
late-relay cancellation coverage now also exercises enabled background audio.
XCUI toggles the production control and checks persistence across relaunch with
large Dynamic Type. The final-head iPhone and iPad gates must pass before merge.

These simulator checks do not prove physical screen-lock audio, headset/AirPods
buttons, Control Center delivery, PiP/AirPlay transitions, provider streaming,
device energy/codec behavior or distribution approval. Record those separately
in #38/#5 before release. Styled ASS, DLNA, WebDAV/SMB, offline/transcoding and
the rest of P4–P6 remain unfinished.
