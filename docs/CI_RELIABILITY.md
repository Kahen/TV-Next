# CI failure investigation — 2026-11-04

Two intermittent failures remained reproducible by inspection on main `62ca3e21`:

- [API run 41467772890](https://github.com/Kahen/TV-Next/actions/runs/41467772890): `TransportIntegrationTest.envelopeLimitAlsoAppliesWhenLengthIsUnknownAndRateIsPerActualPeer` failed at the 300-request assertion. Its burst used the wall clock and straddled a fixed minute window (the log ends at 15:04:00 UTC). A package-local clock seam now fixes the test window; production still uses the system clock. Separate tests deliberately cross 59,999 → 60,000 ms and verify the 10-auth/300-API quotas, peer isolation and Retry-After header.
- [iPad run 41402258256](https://github.com/Kahen/TV-Next/actions/runs/41402258256): the owned search fixture's oversized-request test saw `ConnectionResetError` instead of HTTP 413. The server rejects the advertised length before reading a body; urllib was still sending that body when the socket closed. The test now sends oversized headers without a body and requires an immediate 413, unchanged fixture state and a healthy subsequent request. The server's input limit is unchanged.

The separate iOS DLNA navigation failure in run 41468439938 and alert-dismissal timeout in run 41504522658 already have subsequent changes in main (`19255e48` and `6988511b`). Main's [full gate 41696401543](https://github.com/Kahen/TV-Next/actions/runs/41696401543) passed. These historical failures are not newly claimed fixes in this change. No test retry or skipped assertion is added.

Local validation: all six owned search fixture tests pass. Java 21/Gradle and iPhone/iPad simulator verification run in the existing GitHub CI; this Linux session has only Java 17 and no Xcode. Final-head CI, rather than the historical main result, is required before accepting the changes.
