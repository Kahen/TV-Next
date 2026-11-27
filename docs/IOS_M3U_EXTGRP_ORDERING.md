# Native M3U EXTGRP ordering compatibility

Some M3U exporters place `#EXTGRP:Group` before the following `#EXTINF` record. The native parser now carries that pending group through the `#EXTINF` metadata line instead of resetting it to Uncategorized.

An explicit nonempty `group-title` on `#EXTINF` takes precedence. After consuming any non-comment media-address line, the parser clears pending group state even when that address is rejected; metadata must not bleed into subsequent channels.

The synthetic `ParserSmoke.swift` regression covers both ordering variants, explicit override, per-channel reset, and invalid-address reset. No network, provider, or remote code execution is involved.

Verification: requires running the native Swift parser smoke on a checked-out repository; Xcode simulator and real-device compatibility have not been established by this change.
