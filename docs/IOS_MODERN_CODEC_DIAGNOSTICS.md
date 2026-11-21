# Native playback diagnostics: modern codec labels

The iPhone/iPad playback diagnostics panel reports codecs from AVFoundation's actual media format descriptions (FourCC), rather than guessing from a file extension or streaming URL.

Additional recognized FourCCs:

| FourCC | Display |
| --- | --- |
| `av01` | AV1 (av01) |
| `vp09` | VP9 (vp09) |
| `Opus`, `opus` | Opus |
| `fLaC`, `flac` | FLAC |

Previously recognized H.264, HEVC, AAC, PCM and Apple Lossless formats are unchanged. Unrecognized printable FourCCs are displayed verbatim, and nonprintable FourCCs are displayed in hexadecimal. No URL, codec probe request or external media is introduced.

This is **diagnostics only**. Recognition does not add AVPlayer decoder support, transcode media or imply that any particular device can play AV1, VP9, Opus or FLAC. Unit tests cover recognized codes, unknown printable codes and nonprintable bytes. iPhone/iPad simulator XCTest and full integration must run on the final PR head before merging; physical-device playback remains unverified.
