/* Minimal offline application shell; never cache media URLs, API responses, or user data. */
const CACHE = "tv-next-shell-v1";
const SHELL = ["/", "/index.html", "/manifest.webmanifest", "/icon.svg"];
self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((names) =>
    Promise.all(names.filter((name) => name.startsWith("tv-next-shell-") && name !== CACHE)
      .map((name) => caches.delete(name)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET" || request.mode === "no-cors") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  const isAsset = url.pathname.startsWith("/assets/") && /\.(js|css)$/.test(url.pathname);
  const isShell = SHELL.includes(url.pathname);
  if (!isAsset && !isShell) return;
  // Cache compiled static assets only; bypass any API, video, HLS, or user source request.
  if (isAsset) {
    event.respondWith(caches.open(CACHE).then(async (cache) => {
      const cached = await cache.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      if (response.ok) await cache.put(request, response.clone());
      return response;
    }));
    return;
  }
  event.respondWith(fetch(request).catch(async () => {
    const cached = await caches.match(url.pathname === "/" ? "/index.html" : request);
    return cached || Response.error();
  }));
});
