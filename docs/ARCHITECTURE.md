# Architecture and decisions

Status: ADR-001 accepted for initial implementation.

## System diagram

Clients:
- apps/web: React + TypeScript + Vite, native <video> for compatible streams, hls.js on browsers with Media Source Extensions.
- apps/ios: SwiftUI universal iOS/iPadOS native application, AVKit/AVPlayer. No Java/Android runtime in app.

Backend:
- services/api: Kotlin/JVM 21 + Spring Boot REST; stateless config inspection, playlists and future catalog API.
- services/spider-runtime (future): dedicated process/container per provider runtime with resource and network restrictions.
- packages/contracts: versioned HTTP shapes and API expectations (OpenAPI to be adopted once endpoints stabilize).

No content sources are bundled, and user-provided content is never presumed legal or safe. Start with local import and a well-defined API contract. Production CORS origin configuration is explicit; do not allow arbitrary origins with credentials.

## Trust boundaries and operational rules

1. Web and iOS are untrusted clients. Never treat a submitted URL as permission to fetch arbitrary IP addresses.
2. Config inspection accepts the JSON *content*, never fetches a URL. Media proxy is NOT part of P0.
3. External source config and plugins are untrusted; redact auth headers, cookies and tokens in logs.
4. Spider runtime must be isolated from core API, with no access to its credentials, database, metadata addresses or Docker socket.
5. Untrusted HTML must not be injected into client DOM. Prefer text content and structured React rendering.
6. Native Apple playback is limited by system codecs and application lifecycle. Browser playback depends on codec, origin CORS and provider behavior.
7. Backward compatibility should be measured using fixtures, not assumed from class/method names.

## Configuration and data

P0 POST /api/v1/configs/inspect parses FongMi-style JSON and reports provider descriptors; does not execute them. POST /api/v1/playlists/parse accepts bounded M3U and returns normalized channel entries. GET /api/v1/health returns build-independent status.

P1+ persistence: start with SQLite for a single-instance personal setup if appropriate; adopt PostgreSQL with migrations when multi-user/multi-instance is required. Store user preferences per device/user, not in arbitrary remote scripts. Avoid a database dependency in P0.

## Execution strategy

Use React and SwiftUI as separate clients sharing HTTP semantics, not a WebView wrapper. Split API into controllers, domain services and future persistence. Introduce service-to-runtime RPC only once the first Spider fixtures prove portability.

## Licensing and attribution

TV-Next is a new implementation; do not copy Android code, bundled AARs or copyrighted assets without reviewing license and source provenance. FongMi/TV declares GPLv3. If GPL-covered code is incorporated into a distributed combined work, preserve notices and satisfy corresponding source obligations. Audit transitive dependencies and media player licenses before releases.

## Explicitly out of scope in P0

Java/QuickJS/Python Spider execution, authentication, networking proxying/transcoding, DRM, sideloaded binaries, AirPlay, DLNA, NAS protocols, background sync, EPG parsing and full Android UI parity.
