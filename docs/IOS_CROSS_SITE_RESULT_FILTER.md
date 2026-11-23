# iOS cross-site search result provider filter

The native FongMi cross-provider search view now offers an **All providers** option and one option for each actually searched provider. The selection is presentation-only: it never discards fetched hits, mutates failed-provider retry provenance, changes the original keyword, or issues a new network request.

The provider list uses the selected eligible source keys, not raw subscription entries; duplicate display names include their routing key to disambiguate them. Loading another subscription, starting another search, or leaving the view resets the selection. If the selected provider disappears, the view falls back to all providers.

Unit coverage: valid provider filtering retains order, all-provider mode retains every hit, stale/foreign provider keys cannot hide all results, and selection reconciliation. Xcode XCTest and simulator integration are required before merge; this is not a claim of physical-device validation.
