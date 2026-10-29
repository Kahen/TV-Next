# JVM maintenance security baseline — 2026-10-29

The API now uses Spring Boot 3.5.16 / Spring Framework 6.2.19, Tomcat 10.1.61 and Logback 1.5.38. This stays within the current Jakarta EE 10/Spring 6.2 and Logback 1.5 families. Tomcat/Logback versions are explicit BOM-property overrides because Boot 3.5.16 manages older 10.1.55/1.5.34 releases.

| Component | Previous | New | Primary evidence |
| --- | --- | --- | --- |
| Spring Boot | 3.5.6 | 3.5.16 | [Release](https://github.com/spring-projects/spring-boot/releases/tag/v3.5.16), [source commit](https://github.com/spring-projects/spring-boot/commit/0566f6933049aca6bc5ffc6d559fffade9cd2e0c) |
| Spring Framework | 6.2.11 | 6.2.19 | Boot's pinned [gradle.properties](https://github.com/spring-projects/spring-boot/blob/0566f6933049aca6bc5ffc6d559fffade9cd2e0c/gradle.properties) |
| Tomcat embedded | 10.1.46 | 10.1.61 | [Vendor advisories](https://tomcat.apache.org/security-10.html), [release/download](https://tomcat.apache.org/download-10.cgi), [release tag](https://github.com/apache/tomcat/tree/10.1.61) |
| Logback classic/core | 1.5.18 | 1.5.38 | [Vendor news](https://logback.qos.ch/news.html), [source commit](https://github.com/qos-ch/logback/commit/d04984a41fce42977466f45a2f076f0ee5cc4207) |

Tomcat's vendor advisory range for CVE-2025-61795 includes 10.1.46; later fixes include HTTP/2 cross-user request/response recycling issues such as CVE-2026-101356 (affected 10.1.25–10.1.60). Runtime applicability depends on configured features; no exploitability or complete vulnerability clearance is inferred for this deployment. Logback 1.5.19 addresses CVE-2025-11226 in conditional configuration processing, and 1.5.37 removes Janino expressions as the definitive fix for CVE-2026-13006. The refreshed 1.5.38 line includes those fixes. This project's resolved dependency evidence contains no Janino; affected-version remediation and deployment exposure are separate questions.

## Lock and checksum refresh

The read-only draft [collector 40900514506](https://github.com/Kahen/TV-Next/actions/runs/40900514506) resolved all configurations and ran tests/bootJar with the pinned Gradle 8.14.3/JDK 21 toolchain before collecting the proposed files. It is removed from the final change; normal CI never regenerates evidence. The refreshed baseline has **131 locked modules, 280 verified components and 518 artifact/metadata SHA-256 values**. All 304 unchanged coordinate/filename entries shared with the previous baseline have identical SHA-256 values; no same-version byte drift was accepted.

The first cold Docker build rejected three metadata variants omitted by the hosted warm-cache collector: JUnit BOM 5.10.2/5.11.0-M2 module metadata and the Kotlin coroutines 1.8.0 BOM POM. Their exact checksums are retained from the already accepted #90 cold-cache/candidate baseline (run 40892199041), with explicit origin attributes. Verification remains strict; the fresh Docker build must actually match these existing values. No wildcard or alternate checksum is added. The 518-file final count includes these three retained metadata records.

The evidence validator also enforces stable minimum versions within the four explicitly reviewed maintenance families. Downgrading below the recorded security floors or silently switching to another family fails CI; a future major/minor family needs an explicit policy/compatibility review. Eleven policy tests include known-vulnerable versions and family-change rejection; real Gradle wrong-checksum/missing-lock probes remain required. See [JVM_DEPENDENCY_INTEGRITY.md](JVM_DEPENDENCY_INTEGRITY.md).

Final-head API, PostgreSQL migration/account/remote, Compose/NAS startup/restart/restore, owned browser/native/isolation and candidate host-versus-Docker JAR equality must pass before merge. Candidate library SBOMs are regenerated from their actual shipped bytes where available. The patch does not migrate to Spring Boot 4, provide independent publisher/signature/license review, scan every JVM/container package, or establish NAS/internet/physical Apple acceptance. Those P6 and resource gates remain open.
