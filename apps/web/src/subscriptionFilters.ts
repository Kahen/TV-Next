export interface SiteFilter {key:string;name:string;init?:string;value:{n:string;v:string}[]}
export type SiteFilterMap=Record<string,SiteFilter[]>;
export function initialSiteFilters(filters:SiteFilter[]):Record<string,string>{
  return Object.fromEntries(filters.slice(0,30).map(filter=>[filter.key,filter.init??""]));
}
