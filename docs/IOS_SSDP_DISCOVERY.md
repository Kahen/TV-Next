# Native iOS SSDP M-SEARCH transport (P4, #132)

## Implementation boundary

This is a **dormant transport component**, not a user-visible automatic discovery feature. The existing manual UPnP description URL and AVTransport control remain the only supported iPhone/iPad UI flows. Parent [#114](https://github.com/Kahen/TV-Next/issues/114) remains open. Apple must approve the multicast entitlement, and an actual iPhone/iPad provisioning profile must contain com.apple.developer.networking.multicast before enabling a discovery UI. NSLocalNetworkUsageDescription alone is not proof of permission or multicast authorization. No signed IPA, device interoperability or actual multicast discovery is claimed.

Reference: FongMi/TV's mobile DLNACast.java uses Android jUPnP discovery. This Swift implementation is not a port of Android's jUPnP runtime; it sends only fixed SSDP M-SEARCH requests and consumes bounded responses through the existing NativeSSDPResponse parser.

## Security and resource contract

- Explicit NativeSSDPDiscovery.shared.discover() only; no app lifecycle scan, background discovery, persistent discovered addresses, automatic SOAP control, media requests or home-server upload.
- Fixed 239.255.255.250:1900 UDP destination; exactly two fixed ST values (MediaRenderer:1 and AVTransport:1), MX: 2, multicast TTL 1, no user-provided ST or destination in release builds.
- One scan at a time; at least 10 seconds between starts; at most 3 seconds per scan. Cancellation is checked during transmission and at most every 100 ms while waiting for replies.
- Receive at most 64 UDP packets of at most 4096 bytes each, retaining at most 32 unique LOCATION URLs. Excess, malformed, public, foreign-sender, loopback, duplicate or unsupported responses are discarded.
- The existing NativeSSDPResponse.parse requires strict HTTP 200 syntax, matching ST/USN, an explicitly private IPv4 literal LOCATION whose host matches the datagram sender, and the bounded private-IPv4 URL policy. Discovery results are **candidates**, not trusted devices. A later explicit device-description import must still apply the independent same-origin AVTransport control validation.
- Network errors are surfaced as permission/entitlement guidance, not proof of which Apple permission failed. An empty result can also mean no device, packet loss, network isolation or missing multicast authorization.

## Automated evidence

The SSDPDiscoverySmoke.swift and NativeSSDPDiscoveryTests.swift checks verify exact fixed requests, CRLF framing, disallowed ST injection, URL deduplication and the 32-candidate cap. An owned loopback UDP fixture captures both requests, replies with a loopback LOCATION and an oversized packet, and confirms neither becomes a LAN candidate. scanLoopbackFixture exists only under DEBUG; release code has no alternate network destination. The full CI runs the fixture and both iPhone/iPad simulator XCTest/XCUI, plus Web/API, PostgreSQL, Compose, NAS and Spider isolation.

Simulator/loopback acceptance does **not** establish that the multicast request reaches a TV, that iOS allows it without an entitlement, or that a physical TV supports AVTransport. No Apple distribution credentials are held by this implementation. Keep parent #114 and P4 #5 open until the physical, entitlement and UI criteria are independently met.

## Root-device identity binding prerequisite (#138)

The user-initiated manual UPnP XML importer now extracts a bounded optional root-device `UDN` (ASCII `uuid:` token) and displays it read-only. Missing UDN remains accepted for manual import. Duplicate, foreign-namespace, nested, whitespace/control and oversized UDN values are rejected. A separate `verifyDiscovered` pure validation gate compares a candidate's SSDP `USN` UUID to the root-device UDN (case-insensitively) and rejects mismatches or missing identities before any future candidate can be promoted. The existing same-IP/port AVTransport URL restriction remains in force.

This does **not** enable multicast discovery, automatically fetch descriptions, trust device identity cryptographically, send SOAP, persist LAN identities, or demonstrate real iPhone/iPad entitlement and renderer compatibility. The identity is a self-asserted device identifier, not authentication.

## Bounded SSDP candidate description resolution (#140)

A new **dormant** `NativeSSDPResolver.resolve(candidate)` consumes an already parsed SSDP candidate. Before any HTTP request, it rejects loopback/public/encoded-path locations, unsupported ST values, malformed or overlong UUID-style USN identities and mismatched ST suffixes. The production fetch reuses `NativeDLNADescription.loadDetails`: one private-IPv4 HTTP GET, eight-second deadline, streamed 32 KiB cap, no redirects/cookies/proxy, strict XML and same-IP/port AVTransport control resolution. After fetching, the resolver requires the root-device UDN to match the candidate's USN and revalidates the control URL's origin. Missing/mismatched UDN and foreign control endpoints fail closed. Cancellation is checked before and after I/O.

Owned Swift smoke and iPhone/iPad XCTest cover positive identity matching, malformed candidate rejection **before** the injected fixture loader is called, mismatched UDN/control origins and pre-cancellation. The existing localhost network smoke tests the shared bounded GET transport independently. This is not a multicast UI, authenticated device identity, automatic SOAP cast or real-device test. The injected loader is only for tests; the production overload uses the existing bounded transport. Parent #114 and P4 #5 stay open; physical Apple entitlement/provisioning and real renderer interoperability remain outstanding.
