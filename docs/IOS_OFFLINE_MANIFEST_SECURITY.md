# iOS offline manifest filesystem boundary

The native offline catalog stores only app-generated media identities and display names. On startup, the app now rejects a `catalog.json` symlink or other non-regular filesystem node before attempting to read the manifest. This prevents a redirected manifest from being read through an attacker-controlled filesystem link. A normal regular JSON manifest remains supported.

Regression coverage: `NativeOfflineMediaTests.testStartupRejectsRedirectedOrNonRegularManifestWithoutTouchingOutsideFile` checks a symlink to an external valid JSON file, a directory at the manifest path, preservation of external data, and normal manifest loading.

Validation status: code and XCTest case committed; Xcode simulator and full integration gate have **not** been executed or verified for this branch. No physical-device compatibility, full security audit, Spider sample validation, Apple signing, or release is claimed. Merge only after all required final-HEAD checks pass. This is an iOS offline-storage hardening slice, not completion of P1–P6.
