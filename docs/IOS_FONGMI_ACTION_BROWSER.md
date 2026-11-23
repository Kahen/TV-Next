# Native FongMi HTTPS action browser

The iPhone/iPad FongMi action result can now open a user-selected HTTPS login/action page in an in-app Safari view, without switching to an external browser. The existing external-browser Link remains available for all server-approved links. Only explicit user taps launch the embedded browser.

The native browser uses SafariServices and its own website session. TV-Next does not inject subscription text, backend bearer tokens, request headers or cookies. It does not intercept the page, scrape credentials, assume login completion, or synchronize Safari cookies with the TV-Next API. Closing the sheet returns to the subscription screen; users can manually retry the provider operation. This is an interactive website step, **not** a complete FongMi callback/QR/parser authorization chain.

The embedded-browser policy accepts HTTPS links with a host and no URL userinfo. HTTP and non-web schemes remain ineligible for embedding, even if the backend exposes an external link. Backend action URL validation still applies.

Tests: `NativeActionBrowserPolicyTests` covers HTTPS, missing URLs, HTTP, script/file/data schemes and userinfo. Full Xcode build/simulator execution remains required before merging.
