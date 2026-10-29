# Immutable build inputs

`build-inputs.lock.json` records the reviewed external GitHub Action commit IDs
and Docker image-index SHA-256 digests. Dockerfiles, Compose and CI services use
those exact identities. Multi-platform index digests retain the upstream image's
supported architectures; pinning an amd64 child manifest would prevent ARM NAS
builds. CI rejects mutable or unrecorded action/image references.

Image digests were read from `docker-library/repo-info`, with the metadata's exact
commit, path and blob recorded in the lock. The retained Gradle 8.14.3 metadata
uses its historical commit because the rolling current index no longer lists
that tag. Action annotated tags were dereferenced until reaching actual commit
objects. A digest pin records immutable bytes; it is not a vulnerability scan,
signature verification or independent review of those bytes.

To update an input, inspect its publisher's source and provenance, obtain the
platform-index digest or action commit, update both the lock and references, and
run `python3 scripts/verify_build_pins.py`. Submit the change through the full
integration gate so the actual pinned images are pulled and used in Web/API,
Compose, PostgreSQL/NAS and all three runtime-isolation builds. Never replace a
missing digest with a mutable tag to make CI pass.

Remaining supply-chain gates include Gradle/Maven artifact verification and
dependency locking, JVM/container vulnerability and license scanning, SBOMs for
all shipping artifacts, reproducible output comparison, attestations, signed
distribution and rollback acceptance. These pins do not make P6 complete.
