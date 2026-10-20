# TV-Next

Independent cross-platform media app for Web, iPhone, and iPad, with a self-hosted Kotlin service and a staged compatibility layer for FongMi-style configurations.

> **Early development.** This project does not include any streaming sources. Supply media and sources only when you are authorized to access them. It currently **inspects** FongMi-style JSON but does **not** execute Spider plugins, proxy media, or recreate all Android TV features.

## Current implementation (P1 under development)

| Component | Technology | Current scope |
| --- | --- | --- |
| Web / PWA candidate | React 19 + TypeScript + Vite + hls.js | HTTP(S) M3U import, saved playlists, favorites, recent plays, VOD resume, MP4/HLS playback, JSON config inspection |
| iPhone / iPad | SwiftUI + AVPlayer | Manually enter media, import local M3U **offline** (optional API), saved playlist, favorites, recent plays and VOD progress |
| API | Kotlin + Spring Boot | GET health, POST M3U parse, POST FongMi JSON inspect |
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

## Implementation plan

- [Roadmap from foundation through advanced features](docs/ROADMAP.md)
- [System architecture and security boundaries](docs/ARCHITECTURE.md)
- [Compatibility matrix](docs/COMPATIBILITY.md)
- [Development and smoke test guide](docs/DEVELOPMENT.md)
- [OpenAPI contract](packages/contracts/openapi.yaml)

FongMi/TV is a separate Android project. Any future reuse of GPL-covered code must retain notices and meet license obligations. This repository is **not** an iOS build of the Android APK.

Status: P1 development in progress. CI compilation and unit tests do not replace on-device/network playback verification. No production release yet.
