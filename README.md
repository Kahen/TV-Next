# TV-Next

Independent cross-platform media app for Web, iPhone, and iPad, with a self-hosted Kotlin service and a staged compatibility layer for FongMi-style configurations.

> **Early development.** This project does not include any streaming sources. Supply media and sources only when you are authorized to access them. It supports subscription browsing for type 0/1/2/4, AList/OpenList, danmaku and optional authenticated home-server sync. Type 3 Spider execution, media proxying and remaining advanced Android TV features are still in development.

## Current implementation

| Component | Technology | Current scope |
| --- | --- | --- |
| Web / PWA candidate | React 19 + TypeScript + Vite + hls.js | HTTP(S) M3U import/export, saved playlists, favorites, recents, VOD resume, local media, UTF-8 SRT/WebVTT, PWA shell, FongMi JSON catalog preview (sites and IPTV live groups, no Spider execution) |
| iPhone / iPad | SwiftUI + AVPlayer | Manually enter media, import local M3U **offline** (optional API), saved playlist and M3U export, local Files media and timed UTF-8 subtitles, native playback speed, favorites, recents and VOD progress |
| API | Kotlin + Spring Boot | GET health, POST M3U parse, POST FongMi JSON inspect/catalog preview |
| Infrastructure | Docker Compose, nginx, GitHub Actions | Local self-hosting, Web/API CI, optional manual iOS simulator build |

Local library data is saved **independently per browser or iOS device**. Optional home-server accounts allow explicit revision-based upload/restore; sync conflicts require reading the latest server revision. See [home server deployment and pairing](docs/HOME_SERVER.md). See [local media library design and limits](docs/LOCAL_LIBRARY.md).

## Run with Docker

Prerequisite: Docker with Compose. From the repository root:

```bash
docker compose up --build
```

Open http://localhost:3000 for Web; health endpoint: http://localhost:8080/api/v1/health.

Ports bind to **127.0.0.1** intentionally. Do not expose this development build to the internet.

## Develop without Docker

Requires Java 21, Gradle 8.14.3, Node 22.12+ (22.x) or Node 24, and npm.

```bash
# Terminal 1
cd services/api
gradle bootRun

# Terminal 2
cd apps/web
npm install
npm run dev
```

Open http://localhost:5173. For iOS see [apps/ios/README.md](apps/ios/README.md); XcodeGen and macOS/Xcode are required.

## API endpoints

- `GET /api/v1/health`
- `POST /api/v1/playlists/parse` with JSON `{"content":"#EXTM3U\\n..."}` (normalizes HTTP(S) playlist entries)
- `POST /api/v1/configs/inspect` with JSON `{"content":"{\\\"sites\\\":[]}"}` (static metadata only)

Import content is capped at 1 MiB in the application; large requests should additionally be bounded at the deployment proxy. The browser may still fail to play sources due to CORS, codecs or inaccessible media.

New P2 preview endpoint: `POST /api/v1/catalog/preview` accepts JSON `{"content":"{\\"sites\\":[],\\"lives\\":[]}"}`. Preview only: no external media sources are automatically fetched; only pure direct HTTP(S) IPTV channels can be manually selected for playback. See [catalog limitations](docs/FONGMI_CATALOG.md).

The experimental static MediaProvider supports home, category, local search, detail, and player lookup on manually supplied FongMi Result JSON. It neither fetches network resources nor executes Spider. See [MediaProvider docs](docs/MEDIA_PROVIDER.md).

XMLTV programme guides support local text/Files imports on Web and iOS, plus authenticated saved XMLTV/XMLTV.gz subscriptions with server-side scheduling, persistent per-account cache, bounded downloads and refresh failure recovery. See [XMLTV EPG support](docs/XMLTV_EPG.md).

## Implementation plan

- [Roadmap from foundation through advanced features](docs/ROADMAP.md)
- [System architecture and security boundaries](docs/ARCHITECTURE.md)
- [Compatibility matrix](docs/COMPATIBILITY.md)
- [Development and smoke test guide](docs/DEVELOPMENT.md)
- [Player features and limitations](docs/PLAYER_FEATURES.md)
- [FongMi site/live metadata support](docs/FONGMI_CATALOG.md)
- [MediaProvider contract](docs/MEDIA_PROVIDER.md)
- [XMLTV EPG matching and limits](docs/XMLTV_EPG.md)
- [P0–P6 acceptance evidence](docs/ACCEPTANCE.md)
- [OpenAPI contract](packages/contracts/openapi.yaml)

FongMi/TV is a separate Android project. Any future reuse of GPL-covered code must retain notices and meet license obligations. This repository is **not** an iOS build of the Android APK.

Status: P1–P6 development in progress. See [current implementation and remaining work](docs/IMPLEMENTATION_STATUS.md). CI compilation and unit tests do not replace on-device/network playback verification. No production release yet.

## P3 isolated runtime groundwork

The repository contains an experimental **Node.js, Python and Java 21 bundled-fixture isolation harness** in [services/spider-runtime](services/spider-runtime/README.md), with separate Docker images and a host-side single-invocation controller. This is **NOT** a Spider execution endpoint, remote plugin installer or production sandbox: only reviewable, pre-bundled demonstration fixtures can execute, and Node/Python/Java containers cannot reach the network. The core Spring Boot API, Web/iOS clients, and Docker Compose deployment are unchanged. Real provider compatibility, JVM/JAR support, security assessment and authorized external fixtures remain P3 blockers.

Java fixture logic now implements a reviewable pure-JVM Provider SPI. For a local JAR you own or are permitted to inspect, the static `services/spider-runtime/jar_inspect.py` reports known Android/JNI/native dependencies without executing any code. **A positive candidate report does not authorize executing arbitrary JARs**. See the [Spider runtime guide](services/spider-runtime/README.md).

An optional, default-off [Android Spider bridge](docs/ANDROID_SPIDER_BRIDGE.md)
now connects approved stateless `csp_*` sites to an existing separate FongMi
Android host. It requires administrator-bound init hashes and device login;
does not install Android, support all plugin callbacks, or establish actual ARM
execution compatibility. The [explicit real subscription probe](docs/REAL_SPIDER_COMPATIBILITY.md)
loaded the supplied IDN/image/Base64/comment configuration (49 type-3 sites).

Web dependency installs are locked with `apps/web/package-lock.json`. Use `cd apps/web && npm ci` rather than `npm install` for clean development and CI builds; changes to dependencies require committing an updated lockfile.

The [full cross-platform integration gate](.github/workflows/full-integration.yml) runs Web/API, iOS simulator, real Docker Compose and Spider sandbox verification together on relevant `main` changes (and can be dispatched manually). A green result is a code-integration milestone, **not** signed release, real-media/provider compatibility or Apple device certification.

### Original subscription compatibility

TVBox/FongMi subscription handling is tracked against the original Android source, including type 0 XML, type 1/2 JSON and type 4 HTTP Spider operations. Web/iOS subscription browsing, bounded XML/JSON danmaku overlays and AList/OpenList cloud browsing are under active implementation. See [source mappings, usage and explicit gaps](docs/UPSTREAM_COMPATIBILITY.md). Type 3 Android Spider and direct cloud account authentication are not yet complete. Source-derived compatibility changes retain GPL-3.0 attribution in [NOTICE.md](NOTICE.md).

Web CI audits the locked dependency tree and retains a CycloneDX SBOM. See [dependency security and remaining audit scope](docs/DEPENDENCY_SECURITY.md).
