# iOS subscription URL persistence

The native TVBox/FongMi subscription view now includes an explicit
**记住订阅地址（仅 URL，存入本机钥匙串）** switch and a
**清除保存的订阅地址** button.

- Persistence is **off by default**. On a subsequent app launch, a previously
  saved URL is prefilled; it is **never automatically fetched or played**.
- After the user enables the switch, the URL is saved **only after a successful**
  remote URL-only subscription load on the current request generation.
  Canceled/failed loads, a pasted configuration JSON, Spider extensions,
  action results and authentication responses are never stored.
- Only absolute HTTP(S) URLs up to 4 KiB without spaces/control characters,
  embedded userinfo or fragments are accepted. Query parameters can contain
  access credentials, so the complete URL is stored in the **device-only,
  when-unlocked Apple Keychain**, not UserDefaults, logs, analytics or backups.
  Any server-side HTTP source access still uses the existing transport policy.
- Disabling the switch deletes the saved URL. The clear action also removes
  the currently filled address. Neither action changes an already-open
  ephemeral subscription or media library.
- Local paste/import keeps functioning with no Keychain permission. Keychain
  failure is reported after a successful load; the app does not claim the URL
  was persisted.
- Saved state is one URL per app installation, not a synced account catalog.
  An iOS uninstall or keychain reset may discard it. This is not a Spider
  execution or third-party cloud login feature.

Unit regression covers rejection, update, reading and deletion in the iOS
simulator with a test-specific Keychain item. Device lock/unlock semantics and
live source compatibility are deferred to manual acceptance #38.
