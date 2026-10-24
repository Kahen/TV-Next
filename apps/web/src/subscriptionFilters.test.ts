import { expect,it } from "vitest";
import { readFileSync } from "node:fs";
const fixture=JSON.parse(readFileSync(new URL("../../../fixtures/fongmi-filters-golden.json",import.meta.url),"utf8"));
import { initialSiteFilters } from "./subscriptionFilters";

it("uses original init values and leaves fields without init unfiltered",()=>{
  expect(initialSiteFilters(fixture.expected.movie)).toEqual(fixture.initial);
  expect(initialSiteFilters(fixture.expected.series)).toEqual({sort:""});
  expect(initialSiteFilters([])).toEqual({});
});
