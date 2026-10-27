# FongMi HTTP action: explicit external Web links

The upstream FongMi Result contract allows a `Vod` to contain `action`. On a type-4
HTTP site, this is an action JSON endpoint. Its response can contain `msg` and
`web: {url, mode?, cookie?}`. Web and iOS both call the existing
`POST /api/v1/subscriptions/action` only after the user selects the item.

Both clients show bounded text and a link that must be selected *again* to
open the target. Links must be absolute HTTP(S), non-credentialed URLs, with
no control characters, spaces or backslashes; URL userinfo, unknown modes,
invalid responses and other action commands never trigger navigation.
Web links use `target=_blank` with `rel=noopener noreferrer`; iOS uses
the system external-browser link. No cookie data or home-server token is
forwarded to the destination by TV-Next, and the response is not persisted.

The upstream embedded `mode=view` and `web.cookie` close-when-authenticated
behavior is not replicated. Such results show a warning and allow only
explicit external-browser opening; they do **not** imply successful login.
Other action payloads (including type-3 Spider `action()`, native UI dialogs,
media refresh instructions and proprietary workflows) remain unsupported.
The action HTTP endpoint still relies on the server's bounded,
SSRF-resistant provider transport; do not expose an unaudited server publicly.

Regression fixture: `fixtures/fongmi-action-web-golden.json`, exercised by
Web Vitest and native Swift smoke in the iOS CI job. This does not establish
third-party login, real-source behavior or physical-device acceptance.
Tracks #42 under P2 #3. See [UPSTREAM_COMPATIBILITY.md](UPSTREAM_COMPATIBILITY.md).
