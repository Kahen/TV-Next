# TV-Next

Independent cross-platform media app for Web, iPhone, and iPad, with a self-hosted Kotlin service and a staged compatibility layer for FongMi-style configurations.

> **Early development.** This project does not include any streaming sources. Supply media and sources only when you are authorized to access them. It currently **inspects** FongMi-style JSON but does **not** execute Spider plugins, proxy media, or recreate all Android TV features.

## Current implementation (P1 preview, P2 catalog prototype)

| Component | Technology | Current scope |
| --- | --- | --- |
| Web / PWA candidate | React 19 + TypeScript + Vite + hls.js | HTTP(S) M3U import/export, saved playlists, favorites, recents, VOD resume, local media, UTF-8 SRT/WebVTT, PWA shell, FongMi JSON catalog preview (sites and IPTV live groups, no Spider execution) |
| iPhone / iPad | SwiftUI + AVPlayer | Manually enter media, import local M3U **offline** (optional API), saved playlist and M3U export, local Files media and timed UTF-8 subtitles, native playback speed, favorites, recents and VOD progress |
| API | Kotlin + Spring Boot | GET health, POST M3U parse, POST FongMi JSON inspect/catalog preview |
| Infrastructure | Docker Compose, nginx, GitHub Actions | Local self-hosting, Web/API CI, optional manual iOS simulator build |

Local library data is saved **independently per browser or iOS device**, not synced across devices or backed up to the API. See [local media library design and limits](docs/LOCAL_LIBRARY.md).

## Run with Docker

Prerequisite: Docker with Compose. From the repository root:

```bash
docker compose up --build
```

Open http://localhost:3000 for Web; health endpoint: http://localhost:8080/api/v1/health.

Ports bind to **127.0.0.1** intentionally. Do not expose this development build to the internet.

## Develop without Docker

Requires Java 21, Gradle 8.14.3, Node 22 and npm.

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

An initial **offline XMLTV programme guide** is also available: import a local XMLTV file or paste its contents into the Web **直播节目表** tab after importing an M3U playlist. The API matches `tvg-id` first, then uniquely matched channel names; it never fetches an XMLTV URL or media stream automatically. See [XMLTV EPG support](docs/XMLTV_EPG.md).

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

Status: P1 development in progress. CI compilation and unit tests do not replace on-device/network playback verification. No production release yet.

## P3 isolated runtime groundwork

The repository contains an experimental **Node.js, Python and Java 21 bundled-fixture isolation harness** in [services/spider-runtime](services/spider-runtime/README.md), with separate Docker images and a host-side single-invocation controller. This is **NOT** a Spider execution endpoint, remote plugin installer or production sandbox: only reviewable, pre-bundled demonstration fixtures can execute, and Node/Python/Java containers cannot reach the network. The core Spring Boot API, Web/iOS clients, and Docker Compose deployment are unchanged. Real provider compatibility, JVM/JAR support, security assessment and authorized external fixtures remain P3 blockers.

Java fixture logic now implements a reviewable pure-JVM Provider SPI. For a local JAR you own or are permitted to inspect, the static `services/spider-runtime/jar_inspect.py` reports known Android/JNI/native dependencies without executing any code. **A positive candidate report does not authorize executing arbitrary JARs**. See the [Spider runtime guide](services/spider-runtime/README.md).

Web dependency installs are locked with `apps/web/package-lock.json`. Use `cd apps/web && npm ci` rather than `npm install` for clean development and CI builds; changes to dependencies require committing an updated lockfile.
