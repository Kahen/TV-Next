# Provider observations and private search cache

When logged in, Web/iOS subscription requests carry the home-server device bearer in the API header. Search results are cached for that device for 60 seconds. Request content, subscription base URL, query, page, filters and extension/config identity all participate in a SHA-256 cache key. Anonymous calls retain their previous uncached behavior. Invalid bearers fail authentication rather than silently falling back to anonymous.

Only search pages are cached. Playback URLs/headers, actions and failures are never cached. Use **刷新搜索结果** to bypass the cache; the refreshed result replaces that request's entry. At most 16 entries/device, 64 globally and 8 MiB total are retained; a single result exceeding 1 MiB is not cached. State is in memory and disappears on restart. This is a per-process optimization, not a Redis cluster or durable queue.

The home-server panel shows **本设备来源状态**: network calls, cache hits, failures, last success and latency. These are observations from user-initiated requests, not synthetic background checks or a promise that a provider is currently online. Errors use fixed categories; health records never include source URLs, queries, headers or bearer credentials. Each device gets up to 32 records, with 256 globally and 24-hour inactivity expiry. Other devices and accounts cannot read them.

**清除来源状态和搜索缓存** invalidates in-flight writes as well as existing entries. Revoking a device removes its state; an upstream request completing afterward cannot restore it. Search content remains private to its authenticated device, and library synchronization does not upload these caches.

Automated coverage checks device isolation, expiry, explicit refresh, eviction, anonymous behavior, failure redaction, revocation and clear-during-request races. Real provider compatibility and optional distributed caching remain separate concerns; these counters do not certify source availability or public deployment security.
