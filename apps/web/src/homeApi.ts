import type { LibraryState } from "./library";
export interface Device { id:string;name:string;createdAt:number;expiresAt:number;current:boolean }
export interface HomeSession {token:string;user:{id:string;username:string};device:Device}
export interface RemoteLibrary {revision:number;updatedAt:number;library:LibraryState}
const base=import.meta.env.VITE_API_BASE_URL||"";
export async function homeRequest<T>(path:string,body?:unknown,token?:string):Promise<T>{
  const response=await fetch(base+"/api/v1/home/"+path,{method:body===undefined?"GET":"POST",headers:{...(body===undefined?{}:{"Content-Type":"application/json"}),...(token?{Authorization:"Bearer "+token}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
  const result:unknown=await response.json().catch(()=>null);
  if(!response.ok)throw new Error(result&&typeof result==="object"&&"error" in result?String(result.error):"HTTP "+response.status);
  return result as T;
}

const SESSION_KEY="tv-next-home-session-v1";
export function loadHomeSession():HomeSession|null {
  try { const text=window.sessionStorage.getItem(SESSION_KEY);if(!text||text.length>4096)return null;const value:unknown=JSON.parse(text);
    if(!value||typeof value!=="object")return null;const s=value as HomeSession;
    return typeof s.token==="string"&&/^[A-Za-z0-9_-]{43}$/.test(s.token)&&typeof s.user?.username==="string"&&typeof s.user.id==="string"&&typeof s.device?.id==="string"&&s.device.expiresAt>Date.now()?s:null;
  }catch{return null;}
}
export function saveHomeSession(session:HomeSession|null):void {try{if(session)window.sessionStorage.setItem(SESSION_KEY,JSON.stringify(session));else window.sessionStorage.removeItem(SESSION_KEY);}catch{/* tab remains usable in memory */}}
