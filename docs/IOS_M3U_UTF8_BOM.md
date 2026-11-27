# Native M3U UTF-8 BOM handling

The offline iOS M3U importer accepts a single leading Unicode U+FEFF byte-order mark at the start of a decoded playlist. This allows the `#EXTM3U` header and its catchup defaults to be recognized in UTF-8 BOM-encoded provider exports. No other playlist text is normalized.

A BOM appearing before a later media URL is **not** removed; the URL remains invalid. Existing 1 MiB, 20,000-line and 1,500-channel limits and HTTP(S)-only URL validation remain unchanged. `ParserSmoke.swift` covers both positive and negative cases using synthetic data. No remote source or Spider is executed.

Verification requires the native parser smoke target and iOS simulator CI; this document does not claim either has passed.
