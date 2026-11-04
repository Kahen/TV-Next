# Dependency security and SBOM

Toolchain: Vite 7.3.7 and Vitest 5.0.5, with Node ^22.12, ^24 or >=26 (CI uses Node 22). Test mocks are typed to the component callback contract to accommodate the stricter Vitest 5 types.

Web installs use the committed package-lock.json and `npm ci`. CI audits the complete installed tree, including dev dependencies, and rejects moderate/high/critical npm advisories. The audit endpoint must be reachable; transport errors fail the gate. Security findings must be remediated or explicitly handled in a reviewed change; no blanket advisory suppression is configured.

Each Web CI job generates a CycloneDX JSON SBOM with `npm sbom --sbom-format cyclonedx`. `npm-audit.json` and `sbom-web.cdx.json` are preserved as the `web-dependency-evidence` artifact for 14 days. This records that run's installed tree and registry advisory state. It does not prove absence of vulnerabilities, independently audit license obligations, cover JVM/Python/container images, or provide release provenance/signatures.

The initial 2026-10-23 scan found four affected package nodes in the build/test toolchain: Vite, Vitest, @vitest/mocker and tinypool (one moderate, one high and two critical). These are development/test dependencies; no production-media exploit is inferred from the audit. The exact pinned Vite and Vitest versions are upgraded and the lockfile regenerated with registry integrity hashes; tests/build/audit and the full integration gate must pass before merge.

JVM versions and artifact/metadata SHA-256 checksums are now committed and fail closed through strict Gradle locking/verification; see [JVM_DEPENDENCY_INTEGRITY.md](JVM_DEPENDENCY_INTEGRITY.md). Immutable image/Action inputs, real-browser E2E and unsigned candidate packaging are also implemented; see [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for current evidence.

Remaining P6 work: independent JVM/container vulnerability and license review, complete release-level SBOM/provenance retention, measured budgets, signed/ARM/native artifacts, rollback acceptance and Apple distribution.


The JVM maintenance dependency baseline is refreshed for vendor-published security fixes in Spring Boot/Framework, embedded Tomcat and Logback, with exact version-family regression floors. See [JVM_MAINTENANCE_SECURITY.md](JVM_MAINTENANCE_SECURITY.md) for previous/new versions, source/advisory links, applicability limits and refreshed checksum evidence. This remains distinct from a complete vulnerability/license audit.
