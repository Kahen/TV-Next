# Native manual browser action retry

The iPhone/iPad FongMi type-4 action flow now offers **Complete web operation, then retry** after a valid HTTP(S) browser action. The user explicitly opens the page in an external browser and manually requests the same action again on returning to TV-Next.

This is not a cookie synchronization or OAuth implementation. The app does not read browser credentials, poll login state, automatically follow action URLs, or silently submit requests. A retry reissues the original action through the existing subscription API and may still require a provider-specific authenticated session.

Retry identity is bound to the current site key and subscription content/URL. It is discarded on subscription reload, server/session change, browsing another page, or leaving the view. The button is disabled while a request is running. Only successful action responses that contain a safe external link offer retry.

## Regression

The standalone pure Foundation smoke test is `apps/ios/tests/NativeActionRetrySmoke.swift`; run from `apps/ios` with:

```sh
swiftc TVNext/NativeActionRetryContext.swift tests/NativeActionRetrySmoke.swift -o /tmp/tvnext-action-retry-smoke
/tmp/tvnext-action-retry-smoke
```

It covers same-context acceptance, changed site/config/URL rejection, empty identity, control characters, and oversized actions. Xcode integration/UI testing remains required before merging. This feature does not execute remote Spider code.
