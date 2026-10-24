# Automated browser playback acceptance

`apps/web/e2e/library.spec.ts` exercises the running Web UI through the real Kotlin API/nginx stack. It does not mock browser media APIs or substitute a fake parser response. The Compose smoke workflow runs the same cases in Chromium, Firefox and WebKit, and retains HTML reports plus failure traces/screenshots.

The media fixture is generated locally by FFmpeg from its synthetic test pattern: a 90-second baseline H.264 MP4 plus a segmented HLS playlist. A loopback-only fixture HTTP server implements HEAD/byte ranges/CORS for the browser. No third-party streaming site, account or downloaded commercial video is used. Fixture files live in a temporary directory and are not shipped with the Web build.

Covered paths:

- Import M3U via the real REST parser, decode/render MP4, advance the media clock, store a favorite, seek/pause, reload and resume using the original media URL.
- Demux/decode local HLS segments and retain the selected channel.
- Reject unsupported imports while preserving saved channels; display inaccessible-media errors and recover the prior library after reload.
- Open a local file without persisting its blob URL, import an SRT caption track, navigate with the keyboard and check a narrow viewport for horizontal overflow.

To reproduce, start `docker compose up --build -d`, then run:

```bash
cd apps/web
npm ci
npx playwright install --with-deps chromium firefox webkit
npm run test:e2e
```

Install FFmpeg on the host first. The test fixture server starts/stops with Playwright. `TV_NEXT_TEST_WEB_URL` can override `http://127.0.0.1:3000`. Use an isolated fixture deployment and fresh browser contexts; these tests must not run against an account containing personal media. This is code-level browser evidence, not physical Apple-device, Safari/macOS, DRM, real IPTV/cloud-provider, PiP/background, energy or accessibility certification.
