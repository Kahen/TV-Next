import type { MediaItem, MediaPage, SubscriptionSite } from "./api";

/** A bounded, deterministic subset of FongMi HTTP source search; never executes Spider. */
export interface CrossSiteHit { siteKey: string; item: MediaItem }
export interface CrossSiteSearchResult {
  items: CrossSiteHit[];
  failed: string[];
  warnings: string[];
}

const MAX_SITES = 16;
const MAX_CONCURRENT = 4;
const MAX_PAGES_PER_SITE = 2;
const MAX_ITEMS_PER_PAGE = 40;
const MAX_RESULTS = 600;

function canceled(): DOMException { return new DOMException("Search canceled", "AbortError"); }

export async function searchAcrossSites(
  sites: SubscriptionSite[],
  fetchPage: (site: SubscriptionSite, page: number, signal: AbortSignal) => Promise<MediaPage>,
  signal: AbortSignal
): Promise<CrossSiteSearchResult> {
  if (signal.aborted) throw canceled();
  const seenSites = new Set<string>();
  const eligible = sites.filter(site => {
    if (!site.searchable || site.hidden || ![0, 1, 2, 4].includes(site.type) || seenSites.has(site.key)) return false;
    seenSites.add(site.key);
    return true;
  });
  const selected = eligible.slice(0, MAX_SITES);
  const grouped: CrossSiteHit[][] = Array.from({ length: selected.length }, () => []);
  const failures = new Set<number>();
  const truncated = new Set<number>();
  let cursor = 0;

  await Promise.all(Array.from({ length: Math.min(MAX_CONCURRENT, selected.length) }, async () => {
    while (cursor < selected.length) {
      if (signal.aborted) throw canceled();
      const index = cursor++;
      const site = selected[index];
      const seenItems = new Set<string>();
      try {
        for (let page = 1; page <= MAX_PAGES_PER_SITE; page++) {
          if (signal.aborted) throw canceled();
          const response = await fetchPage(site, page, signal);
          if (signal.aborted) throw canceled();
          for (const item of response.items.slice(0, MAX_ITEMS_PER_PAGE)) {
            if (!item || typeof item.id !== "string" || typeof item.name !== "string" || seenItems.has(item.id)) continue;
            seenItems.add(item.id);
            grouped[index].push({ siteKey: site.key, item });
          }
          if (!response.hasMore) break;
          if (page === MAX_PAGES_PER_SITE) truncated.add(index);
        }
      } catch (error) {
        if (signal.aborted) throw canceled();
        failures.add(index);
      }
    }
  }));
  if (signal.aborted) throw canceled();
  const all = grouped.flat();
  const warnings: string[] = [];
  if (eligible.length > MAX_SITES) warnings.push(`仅搜索前 ${MAX_SITES} 个可用站点，其余 ${eligible.length - MAX_SITES} 个未请求。`);
  if (truncated.size) warnings.push(`${truncated.size} 个站点仍有更多结果；每站最多检索 ${MAX_PAGES_PER_SITE} 页。`);
  if (all.length > MAX_RESULTS) warnings.push(`仅显示前 ${MAX_RESULTS} 条结果。`);
  return {
    items: all.slice(0, MAX_RESULTS),
    failed: selected.filter((_, index) => failures.has(index)).map(site => site.name),
    warnings
  };
}
