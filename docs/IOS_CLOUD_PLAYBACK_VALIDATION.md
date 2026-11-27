# Native cloud playback response validation

The iOS AList/OpenList browser now validates the returned `cloud/play` resource before passing it to AVPlayer. Only HTTP(S) media URLs without embedded credentials, fragments, whitespace or control characters are accepted. The response may include at most 32 HTTP headers; header names must be valid HTTP tokens, and values cannot contain control characters (including CR/LF). URL and header sizes are bounded.

This validation protects the client from malformed or hostile relay responses. It does **not** authenticate the media origin, prevent access to private network addresses, implement SMB, or replace server-side SSRF protection. Valid provider `Authorization` and `Referer` headers are preserved for authorized playback.

`NativeCloudPlaybackValidationTests` covers accepted HTTP(S) playback and headers, rejected schemes/credentials/fragments/control characters, and rejected malformed headers. Run the full iOS XCTest and simulator CI before merging; no external Spider execution or real cloud credentials are needed.
