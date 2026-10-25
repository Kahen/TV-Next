# P2 cross-provider search (bounded Web implementation)

This increment improves the existing subscription **跨站搜索** action without introducing remote plugin execution. Search applies only to non-hidden, searchable type 0/1/2/4 HTTP providers from the user's loaded subscription. Type 3 Spider sites are deliberately excluded.

- At most **16 unique sites**, **4 concurrent requests**, **2 pages per site**, **40 items per page**, and **600 displayed results**. Each request uses the existing 20-second client timeout and server-side network restrictions.
- The browser aborts pending requests on cancel, subscription reload, session-token change, or unmount. Superseded responses cannot replace newer results.
- Results appear in the subscription's site order, then page order, regardless of network completion order. Duplicate video IDs are suppressed **within** a site but preserved across different sites (IDs are provider-scoped).
- A failed provider does not discard successful results; its display name is reported without upstream exception contents or tokens. Explicit warnings report site/page/result truncation.
- Clicking a result requests detail from its original site; no arbitrary Spider/JavaScript execution occurs in the browser.

Automated tests cover concurrent scheduling, duplicate handling, pagination, cancellation, partial failures and excluded sites, plus Web component integration. This is **not** exhaustive search: deeper pages and sites past the cap are omitted with warnings. Real permitted provider samples, native cross-provider search UI parity, server quotas and physical playback acceptance remain outstanding under Issue #3 and docs/ACCEPTANCE.md.
