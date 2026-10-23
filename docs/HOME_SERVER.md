# Home server: accounts, devices, sync and remote control

The account service is opt-in. Local playback/imports remain available without an account. Library sync is an explicit read/upload/restore flow; it never silently overwrites another device's revision.

## Local Compose

```
TV_NEXT_REGISTRATION_OPEN=true docker compose up --build -d
```

Open http://localhost:3000, select **家庭服务器**, create an account (12–128 character password). Then close registration by restarting with `TV_NEXT_REGISTRATION_OPEN=false`. The default is closed; registration cannot be toggled from an untrusted client. The regular Compose stack stores its H2 database in the named `api-data` volume. Tests use isolated in-memory databases.

Web keeps the home-session bearer token in sessionStorage for the current tab. iOS stores it under the exact server URL in the device Keychain (`WhenUnlockedThisDeviceOnly`). Tokens last 90 days, contain 256 random bits and are stored only as SHA-256 hashes on the server. Passwords use per-user random salts and PBKDF2-HMAC-SHA256 with 600,000 iterations; the iteration count is stored for future migrations. OpenList credentials remain separate and are not part of library synchronization.

Creating a pairing code requires a valid device. The 64-bit random code is valid for five minutes and can be claimed only once. A newly created code replaces that device's previous code. Account creation/login/pair claims are limited to 10 requests/minute per actual peer address; other API requests are limited to 300/minute. Reverse proxies share the peer quota because arbitrary forwarded headers are not trusted.

Device listing and revocation apply only to the authenticated user's devices. Revoking a token prevents new REST access and closes its remote channel when revoked through the API. Per-user library storage accepts only version-1 channel/favorite/recent/progress data and excludes private request-header credentials.

## NAS / PostgreSQL

Use the independent `compose.nas.yaml` stack. Set `TV_NEXT_DB_PASSWORD` yourself (required, no default password). Optional configuration:

- `TV_NEXT_REGISTRATION_OPEN=true` for initial account creation, then false.
- `TV_NEXT_BIND_ADDR` defaults to 127.0.0.1; choose your intended LAN bind address.
- `TV_NEXT_CORS_ALLOWED_ORIGINS` for your exact Web origin, especially with HTTPS reverse proxying.
- `TV_NEXT_LAN_ORIGINS` for exact private OpenList/provider destinations; loopback and metadata/link-local services remain denied.

```
docker compose -f compose.nas.yaml up --build -d
```

PostgreSQL has no published host port. The API runs without Linux capabilities, with a read-only root filesystem, bounded memory/PIDs and a temporary directory; PostgreSQL data uses `pg-data`. Flyway applies versioned migrations. H2 and PostgreSQL paths are independently checked in CI. Actual NAS capacity, filesystem behavior and load require final deployment acceptance.

For remote access, terminate HTTPS with your own reverse proxy and configure the same exact origin on the API. For example, a Caddy site can reverse-proxy your chosen hostname to `127.0.0.1:3000`. Nginx forwards WebSocket upgrades and preserves the external Host/port. Do not publish the database or API management endpoints through that proxy.

## Library consistency and backups

`GET /api/v1/home/library` returns `{revision, updatedAt, library}`. `POST` requires `{expectedRevision, library}`. An atomic SQL compare-and-set returns HTTP 409 on conflict; both the server snapshot and the local copy remain intact. Read the latest revision before explicitly choosing which data to upload or restore. Web has JSON import/export; native library read/upload/restore uses the identical version-1 shape.

Back up PostgreSQL before upgrades:

```
docker compose -f compose.nas.yaml exec -T db pg_dump -U tvnext -d tvnext -Fc > tvnext.dump
```

Restore to the intended test/restore instance with `pg_restore`. Do not run `docker compose down -v` on a server whose data you want to retain. Restoring a database and rolling back an application image must use a compatible migration version; an older binary is not automatically compatible with newer schema migrations.

## Authorized real-time remote control

Web and iOS connect as their own authenticated device. The REST API issues a random single-use handshake ticket lasting 30 seconds. A WebSocket URL contains only that ticket, never the reusable device bearer token. Origin restrictions and per-user ownership checks apply. Reconnect obtains a fresh ticket. Each connection accepts at most 120 incoming text messages per minute.

Commands are limited to `PLAY`, `PAUSE`, `SEEK` and `LOAD` with bounded HTTP(S) URLs/positions. Sender and receiver must belong to the same account. An offline target returns HTTP 409. The receiver sends an explicit positive/negative acknowledgement; the sender can query the result for five minutes. Remote-control state is ephemeral and is not a durable task queue. Browser autoplay restrictions or unsupported seeking produce rejection rather than a fabricated playback success.

## Diagnostics and remaining scope

The private API exposes Actuator health and Prometheus metrics; nginx publishes only `/api/`, so management URLs are not proxied by the default Web stack. Requests receive a generated `X-Request-Id`; logs record route templates, status and duration without bodies, queries or authentication material. No tokens or pairing codes should be added as metric labels.

No public deployment security audit, real-device/background media acceptance or NAS load benchmark is claimed here. Provider/EPG scheduling, shared caches, a media byte relay, and the remaining Spider/advanced playback/release work stay separately tracked in P3–P6.
