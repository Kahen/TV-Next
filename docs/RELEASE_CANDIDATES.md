# Unsigned Web/server release candidates

The **Unsigned Web and Server Release Candidate** workflow builds versioned Web,
API JAR, Linux amd64 Docker archives and the corresponding exact GPL source,
LICENSE/NOTICE, Web dependency audit/SBOM, build-input lock, image identities and SHA256SUMS. The manifest
records the tested source commit and explicitly marks the candidate unsigned.
This is an experimental compatibility subset, not completion of P1–P6. No IPA,
TestFlight, App Store, real-device or real Spider execution result is included.

PR packaging checks exercise directory/version boundaries, real Web/API/image
builds, archive load and checksum verification without creating a release. The API
JAR built on the hosted runner must also be byte-identical to `/app/api.jar`
extracted from the independently compiled pinned Docker build; mismatch fails
candidate generation. This checks the two actual distributed API binaries, not
the reproducibility of every toolchain/container layer. Manual
dispatch first requires the entire cross-platform integration gate for the same
revision. Set a unique version (`v0.2.0-rc.1`, for example). By default only a
14-day workflow artifact is produced. Explicitly selecting **create_draft** on
main creates a draft GitHub Release with all candidate attachments. Publishing
the draft is a separate release decision after the remaining acceptance gates;
the workflow does not automatically publish it or overwrite an existing version.

Verify `sha256sum --check SHA256SUMS` before using an archive, and inspect
`manifest.json` for its exact source and platform. SHA-256 establishes matching
bytes, not publisher authenticity. Extract the Web archive for a static host,
run the API JAR with Java 21, or `gzip -dc *-linux-amd64-images.tar.gz | docker load`
to load `tvnext/api:<version>` and `tvnext/web:<version>`. Use a Compose image
override with those tags; retain the deployment's existing database credentials,
volumes and reviewed network policy. ARM Docker packages remain pending.

Before upgrading, take and verify the database backup described in HOME_SERVER.md.
Retain the prior candidate and image IDs. To roll back, stop writes and restore
both the previous images and its compatible database backup; never assume a
forward Flyway migration can be reversed by downgrading only the JAR. Actual
production upgrade/rollback drills and signed provenance remain acceptance work.

Web tar metadata and JAR entry ordering/timestamps are stabilized. Container
archives are not claimed bit-reproducible. Remaining P6 gates include full JVM/
container/license audit and SBOMs, independently verified provenance/signatures,
performance budgets, real-provider/device acceptance and Apple distribution.
