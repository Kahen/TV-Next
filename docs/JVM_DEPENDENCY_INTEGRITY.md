# JVM dependency integrity

The API uses Gradle 8.14.3 and JDK 21. The committed `services/api/gradle.lockfile` records 131 exact compile/runtime/test/tooling module versions. `gradle/verification-metadata.xml` records 518 SHA-256 checksums across 280 resolved components, including build plugins, POM/module metadata, parent BOMs and artifacts. BOM metadata is not an assertion that every managed library ships at runtime.

All resolvable project configurations use Gradle strict dependency locking. API CI, PostgreSQL tests, Docker compilation and unsigned candidate compilation explicitly use strict dependency verification. There are no blanket trusted-artifact rules, ignored checksum exceptions or fallback to lenient/off verification. CI validates coverage and policy and never regenerates the approved files. Missing lock state, changed resolution, unlisted artifacts and wrong artifact/metadata bytes must fail.

## Evidence and limits

Initial checksums were calculated by the Gradle 8.14.3 hosted JDK 21 build in [bootstrap run 40891396261](https://github.com/Kahen/TV-Next/actions/runs/40891396261), from the project repositories (Maven Central and the Gradle plugin portal). That draft ran dependencies, tests and bootJar before collecting the exact generated files. This is a recorded bootstrap trust point, not independent publisher provenance, PGP identity verification, vulnerability or license clearance. Verification prevents silently accepting different bytes after this baseline; a malicious original artifact or compromised baseline review remains outside that guarantee.

The JVM Dependency Integrity workflow performs a real build with the committed files, then uses disposable project copies and the populated Gradle cache. An unchanged offline copy must succeed. Replacing every expected SHA-256 with zeros must produce Gradle's dependency-verification failure; restoring checksums and removing the lock must produce strict-lock failure during actual runtime resolution. Failure for an unrelated reason does not pass these probes. Parser regressions also reject mutable versions, incomplete configurations, missing module evidence, weak/alternate checksums, duplicate evidence, disabled metadata verification and blanket trust.

The initial #90 baseline (132 modules / 519 hashes) was refreshed by the maintenance security update. See [JVM_MAINTENANCE_SECURITY.md](JVM_MAINTENANCE_SECURITY.md) for the current vendor versions, collector evidence, unchanged-byte comparison and family floors. This historical bootstrap link is retained as provenance of the first baseline.

## Intentional updates

1. Change a declared dependency/plugin version in a reviewed branch.
2. With the pinned Gradle/JDK toolchain, run from `services/api`:

   ```sh
   gradle dependencies test bootJar --write-locks --write-verification-metadata sha256 --no-daemon
   ```

3. Review coordinate/version changes and each new checksum against the intended upstream artifact/repository. Generating metadata is not approval. Do not add wildcard trust or switch verification off to clear a failure.
4. Verify a clean pinned Docker build as well as the host build: warm caches can omit metadata variants from checksum generation. Retain already accepted exact hashes only with provenance and actual strict cold-build verification; a missing or changed checksum must not be silently trusted.
5. Commit both generated files. Run the evidence validator, negative probes, API/PostgreSQL, real Docker build, unsigned candidate byte-equality packaging and the full integration gate. An unchanged library version with different bytes needs investigation.

Gradle user guidance: [locking](https://docs.gradle.org/current/userguide/dependency_locking.html) and [verification](https://docs.gradle.org/current/userguide/dependency_verification.html). Remaining P6 work includes independent dependency/license review, JVM/container vulnerability scanning and release-level SBOM/provenance/signatures. Physical Apple, ARM/native distribution and rollback acceptance remain separate.
