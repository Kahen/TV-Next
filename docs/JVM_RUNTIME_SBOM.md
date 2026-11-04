# JVM shipped-library SBOM

API CI and unsigned candidate packaging produce a deterministic CycloneDX 1.6 JSON inventory of the libraries actually embedded in the final Spring Boot JAR's `BOOT-INF/lib/`. Each embedded JAR is streamed through SHA-256 and must match an exact artifact filename, coordinate and checksum in the committed Gradle verification metadata. Unknown, changed or ambiguous libraries fail generation; the report is not just a list copied from the build declaration or the larger BOM/parent-metadata graph.

Each component includes its Maven package URL (with a classifier when present), exact version, archive path and actual embedded-byte SHA-256. The application component contains the whole API JAR SHA-256 and supplied build/release version. A property records the exact verification-metadata file hash. Ordering is stable and there is no random ID or current-time field, so repeated generation from the same inputs produces identical JSON.

API CI retains `api-dependency-evidence` for 14 days, containing the SBOM, module lock and checksum baseline. Candidate packaging independently regenerates `sbom-api.cdx.json` from the exact JAR attachment and includes both Gradle evidence files under the candidate manifest and SHA256SUMS. The existing host-versus-Docker byte-equality gate binds the same inventory to the API binary in the Docker image.

Run from the repository root after a strict Gradle bootJar build:

```sh
python3 scripts/generate_jvm_sbom.py --jar services/api/build/libs/tv-next-api-0.1.0-SNAPSHOT.jar --version 0.1.0-SNAPSHOT --output services/api/build/reports/sbom-api.cdx.json
python3 -m unittest discover -s scripts -p test_generate_jvm_sbom.py
```

Owned regression archives verify coordinate/hash binding, full-JAR identity, deterministic output, unknown/tampered libraries, duplicate/unsafe archive paths, classifier identity, ambiguous evidence and size/count/expansion limits. The real candidate workflow must also pass against the production bootJar; synthetic archives alone do not establish production inventory coverage.

This is a flat shipped-library inventory. It does not infer direct/transitive dependency edges, licensed-use approval, vulnerability clearance or publisher authenticity. It excludes application-class source inventory, test/build-only dependencies not shipped, the JDK, OS/base-image packages, Web/npm and Spider runtime dependencies. Complete container/runtime/license/provenance/signature coverage remains P6 work. See [JVM_DEPENDENCY_INTEGRITY.md](JVM_DEPENDENCY_INTEGRITY.md) for baseline trust and update rules and [RELEASE_CANDIDATES.md](RELEASE_CANDIDATES.md) for distribution limits.

## Spring Boot packaging boundary

The initial production API CI for PR #91 (run [40894120708](https://github.com/Kahen/TV-Next/actions/runs/40894120708)) failed closed because Spring Boot 3.5.6 inserted `spring-boot-jarmode-tools-3.5.6.jar` into `BOOT-INF/lib/` even though that JAR was not part of the reviewed Gradle runtime checksum baseline. The service and Docker image execute `java -jar` directly and do not use Spring Boot's jarmode extraction. The `bootJar` task now sets `includeTools.set(false)` to exclude this unused tool rather than fabricating a checksum, weakening matching rules or approving a new artifact without review. The next final-head API and unsigned candidate builds must prove that all remaining shipped libraries match the committed baseline, and the existing Docker/host JAR byte-equality gate must still pass. This is not an independent dependency provenance audit.
