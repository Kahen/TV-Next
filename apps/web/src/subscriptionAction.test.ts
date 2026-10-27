import { expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { interpretSubscriptionAction, safeActionUrl } from "./subscriptionAction";

const fixture = JSON.parse(readFileSync(new URL("../../../fixtures/fongmi-action-web-golden.json", import.meta.url), "utf8")) as {
  cases: {name:string;body:unknown;url:string|null;message:string|null;warning:boolean}[];
};
it.each(fixture.cases)("interprets FongMi action contract: $name", ({body,url,message,warning}) => {
  const result = interpretSubscriptionAction(body);
  expect(result.web?.url ?? null).toBe(url);
  expect(result.message).toBe(message);
  expect(result.unsupported || result.web?.hasUnsupportedBrowserFeatures === true).toBe(warning);
});
it("rejects unsafe navigation and treats malformed roots as unsupported", () => {
  expect(safeActionUrl("https://example.org\n.evil.test")).toBeNull();
  expect(safeActionUrl("https://example.org\\@evil.test")).toBeNull();
  expect(safeActionUrl("https://user@example.org")).toBeNull();
  expect(safeActionUrl("data:text/html,hi")).toBeNull();
  expect(safeActionUrl("https://example.org/" + "x".repeat(5000))).toBeNull();
  expect(interpretSubscriptionAction([]).unsupported).toBe(true);
  expect(interpretSubscriptionAction({web:{url:"https://example.org/", mode:"bad"}}).web).toBeNull();
});
