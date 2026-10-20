# Developer quickstart

Requirements: Node.js 22 and npm; JDK 21 and Gradle 8.14.3 (or Docker Compose); macOS/Xcode + XcodeGen for the iOS app.

## Fast path: Docker Compose

From the repository root:

    docker compose up --build

Browse http://localhost:3000 for Web. The API is at http://localhost:8080/api/v1/health. Ports are bound to loopback only by default. For remote NAS access, explicitly configure a trustworthy reverse proxy, TLS, authentication and network restrictions before binding to external interfaces.

## Development mode

Terminal A:

    cd services/api
    gradle bootRun

Terminal B:

    cd apps/web
    npm install
    npm run dev

Browse http://localhost:5173. Vite proxies /api to localhost:8080. Note: current Web lockfile generation is pending; do not claim reproducible npm CI until the lockfile is committed.

## API smoke tests

Health:

    curl http://localhost:8080/api/v1/health

M3U:

    curl -X POST http://localhost:8080/api/v1/playlists/parse -H 'Content-Type: application/json' -d '{"content":"#EXTM3U\n#EXTINF:-1 group-title=\"Demo\",Example\nhttps://example.org/test.m3u8"}'

FongMi JSON inspection (no Spider executed):

    curl -X POST http://localhost:8080/api/v1/configs/inspect -H 'Content-Type: application/json' -d '{"content":"{\"spider\":\"./spider.jar\",\"sites\":[{\"key\":\"demo\",\"name\":\"Example\",\"type\":3}]}"}'

Use only content you are authorized to access. The example.org URL is an illustrative placeholder, not a working video stream. HLS.js cannot bypass browser CORS rules; production media availability requires compatible sources.

## Native iOS

See apps/ios/README.md. On simulator, the backend address may be localhost. On physical devices use a reachable HTTPS endpoint and honor Apple App Transport Security. No third-party JAR or Python plugins execute on device.

## Testing

    cd services/api && gradle test
    cd apps/web && npm install && npm run build

CI checks both, while macOS iOS simulator build can be triggered separately under GitHub Actions. Build success must be verified before tagging a release.

## Design and security

The P0 API only processes supplied text; it does not fetch external URLs. No authentication/persistent storage exists yet; do not expose this development service publicly. There is no unrestricted forward proxy, automated Spider loading or bundled source catalog.
