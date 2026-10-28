import { describe, expect, it } from "vitest";
import type { MediaItem, MediaPage, SubscriptionSite } from "./api";
import { searchAcrossSites } from "./crossSiteSearch";

function site(key: string): SubscriptionSite {
  return { key, name: key, type: 4, searchable: true, hidden: false, support: "http" };
}
function item(id: string): MediaItem {
  return { id, name: id, categoryId: null, categoryName: null, poster: null, remarks: null, year: null };
}
function page(items: MediaItem[], hasMore = false): MediaPage {
  return { items, hasMore, categories: [], total: items.length, page: 1, pageSize: 40, provider: "test" };
}

describe("bounded cross-provider search", () => {
  it("keeps source order, deduplicates within a source and retains identical IDs across sources", async () => {
    let active = 0, peak = 0;
    const calls: string[] = [];
    const result = await searchAcrossSites(Array.from({ length: 6 }, (_, i) => site(String(i))),
      async (source, number) => {
        active++; peak = Math.max(peak, active); calls.push(source.key + ":" + number);
        await new Promise(resolve => setTimeout(resolve, source.key === "0" ? 6 : 1));
        active--;
        if (source.key === "0" && number === 1) return page([item("shared")], true);
        if (source.key === "0") return page([item("shared"), item("second")]);
        return page([item("shared")]);
      }, new AbortController().signal);
    expect(peak).toBeGreaterThan(1);
    expect(peak).toBeLessThanOrEqual(4);
    expect(calls).toContain("0:2");
    expect(result.items.map(x => x.siteKey + ":" + x.item.id))
      .toEqual(["0:shared", "0:second", "1:shared", "2:shared", "3:shared", "4:shared", "5:shared"]);
    expect(result.failed).toEqual([]);
  });

  it("bounds site fan-out and pages, and reports incomplete coverage", async () => {
    const calls: string[] = [];
    const result = await searchAcrossSites(Array.from({ length: 20 }, (_, i) => site(String(i))),
      async (source, number) => {
        calls.push(source.key + ":" + number);
        return page([item(source.key + "-" + number)], true);
      }, new AbortController().signal);
    expect(calls).toHaveLength(32);
    expect(calls).not.toContain("16:1");
    expect(calls).not.toContain("0:3");
    expect(result.items).toHaveLength(32);
    expect(result.warnings.join(" ")).toMatch(/前 16 个|2 页/);
  });

  it("keeps successful results when another source fails, without exposing exception details", async () => {
    const result = await searchAcrossSites([site("a"), site("b")], async source => {
      if (source.key === "a") throw new Error("secret token must not be shown");
      return page([item("ok")]);
    }, new AbortController().signal);
    expect(result.items.map(x => x.item.id)).toEqual(["ok"]);
    expect(result.failed).toEqual(["a"]);
    expect(JSON.stringify(result)).not.toContain("secret token");
  });

  it("rejects cancellation without returning stale partial results", async () => {
    const controller = new AbortController();
    let calls = 0;
    await expect(searchAcrossSites([site("a")], async () => {
      calls++;
      controller.abort();
      return page([item("stale")], true);
    }, controller.signal)).rejects.toMatchObject({ name: "AbortError" });
    expect(calls).toBe(1);
  });

  it("does not request hidden, unsupported, unsearchable or duplicate sites", async () => {
    const sources = [site("a"), site("a"), { ...site("b"), type: 3 }, { ...site("c"), hidden: true }, { ...site("d"), searchable: false }];
    const keys: string[] = [];
    await searchAcrossSites(sources, async source => { keys.push(source.key); return page([]); }, new AbortController().signal);
    expect(keys).toEqual(["a"]);
  });
  it("includes only server-approved Android sites and bounds their host concurrency", async () => {
    const sources = [{...site("disabled"),type:3}, ...Array.from({length:5},(_,i)=>({...site(String(i)),type:3,support:"android-spider"}))];
    let active=0,peak=0;
    const calls:string[]=[];
    const result=await searchAcrossSites(sources,async source=>{
      calls.push(source.key);active++;peak=Math.max(peak,active);
      await new Promise(resolve=>setTimeout(resolve,1));active--;
      return page([item("ok")]);
    },new AbortController().signal);
    expect(calls).not.toContain("disabled");expect(calls).toHaveLength(5);
    expect(peak).toBe(2);expect(result.items).toHaveLength(5);
  });
});
