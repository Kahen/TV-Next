import { expect,it } from "vitest";
import fixture from "../../../fixtures/fongmi-filters-golden.json";
import { initialSiteFilters } from "./subscriptionFilters";

it("uses original init values and leaves fields without init unfiltered",()=>{
  expect(initialSiteFilters(fixture.expected.movie)).toEqual(fixture.initial);
  expect(initialSiteFilters(fixture.expected.series)).toEqual({sort:""});
  expect(initialSiteFilters([])).toEqual({});
});
