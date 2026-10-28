package dev.tvnext.api

import com.fasterxml.jackson.databind.ObjectMapper
import java.security.MessageDigest
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.event.TransactionalEventListener
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class ProviderHealth(val id: String,val siteKey: String,val networkCalls: Long,val cacheHits: Long,val failures: Long,
    val lastAttemptAt: Long,val lastSuccessAt: Long?,val lastLatencyMs: Long,val lastError: String?)

/** Device-private, bounded, ephemeral search cache. Playback URLs/headers are never cached. */
@Service
class ProviderGateway(private val accounts: HomeAccounts,private val provider: SubscribedProvider,private val mapper: ObjectMapper) {
    private data class CacheKey(val principal: HomePrincipal,val digest: String)
    private data class Cached(val bytes: ByteArray,val expires: Long)
    private data class HealthKey(val principal: HomePrincipal,val source: String,val site: String)
    private data class Observed(var value: ProviderHealth,var touched: Long)
    private val cache=LinkedHashMap<CacheKey,Cached>(16,0.75f,true)
    private val health=LinkedHashMap<HealthKey,Observed>(16,0.75f,true)
    private val generations=mutableMapOf<HomePrincipal,Any>()
    private var bytes=0
    internal var now: ()->Long = System::currentTimeMillis

    fun page(op: String,r: SiteRequest,auth: String?): ProviderPage {
        val p=principal(auth,r) ?: return provider.page(op,r)
        val key=sourceKey(p,r)
        val generation=generation(key)
        if(op!="search")return observed(key,generation) { provider.page(op,r) }
        val cacheKey=CacheKey(p,hash(mapper.writeValueAsBytes(r.copy(bypassCache=false))))
        if(!r.bypassCache) {
            val found=synchronized(this) { prune();cache[cacheKey]?.bytes }
            if(found!=null) {
                synchronized(this) {
                    if(generations[p]===generation) {
                        val record=record(key);record.value=record.value.copy(cacheHits=record.value.cacheHits+1)
                        record.touched=now()
                    }
                }
                return mapper.readValue(found,ProviderPage::class.java)
            }
        }
        val result=observed(key,generation) { provider.page(op,r) }
        val encoded=mapper.writeValueAsBytes(result)
        if(encoded.size<=1_048_576)synchronized(this) {
            prune()
            // Revoke may have committed while an upstream request was running.
            if(generations[p]!==generation || accounts.devices(p).none { it.id==p.deviceId })return@synchronized
            cache.remove(cacheKey)?.let { bytes-=it.bytes.size }
            cache[cacheKey]=Cached(encoded,now()+60_000);bytes+=encoded.size
            while(cache.keys.count { it.principal==p }>16)remove(cache.keys.first { it.principal==p })
            while(cache.size>64 || bytes>8_388_608)remove(cache.keys.first())
        }
        return result
    }
    fun detail(r: SiteRequest,auth: String?)=execute(r,auth) { provider.detail(r) }
    fun play(r: SiteRequest,auth: String?)=execute(r,auth) { provider.play(r) }
    fun action(r: SiteRequest,auth: String?)=execute(r,auth) { provider.action(r) }
    private fun <T> execute(r: SiteRequest,auth: String?,work: ()->T): T {
        val p=principal(auth,r) ?: return work()
        val key=sourceKey(p,r)
        return observed(key,generation(key),work)
    }
    private fun principal(auth: String?,r: SiteRequest): HomePrincipal? {
        if(auth!=null)return accounts.principal(auth)
        if(provider.requiresAuthentication(r))throw ResponseStatusException(HttpStatus.UNAUTHORIZED,"Spider execution requires a signed-in device")
        return null
    }
    private fun sourceKey(p: HomePrincipal,r: SiteRequest): HealthKey {
        if(r.siteKey.isBlank() || r.siteKey.length>200 || r.url.length>4096 || r.content.toByteArray(Charsets.UTF_8).size>1_048_576)
            throw ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid source request")
        return HealthKey(p,hash((r.url+"\u0000"+r.content).toByteArray(Charsets.UTF_8)),r.siteKey)
    }
    @Synchronized private fun generation(key: HealthKey): Any {
        prune();record(key)
        return generations.getOrPut(key.principal) { Any() }
    }
    private fun <T> observed(key: HealthKey,generation: Any,work: ()->T): T {
        val start=now()
        synchronized(this) {
            if(generations[key.principal]===generation) {
                val record=record(key);record.touched=start
                record.value=record.value.copy(networkCalls=record.value.networkCalls+1,lastAttemptAt=start)
            }
        }
        try {
            val result=work()
            synchronized(this) {
                if(generations[key.principal]===generation && accounts.devices(key.principal).any { it.id==key.principal.deviceId }) {
                    val record=record(key);record.touched=now()
                    record.value=record.value.copy(lastSuccessAt=now(),lastLatencyMs=(now()-start).coerceAtLeast(0),lastError=null)
                }
            }
            return result
        } catch(error: Exception) {
            synchronized(this) {
                health[key]?.takeIf { generations[key.principal]===generation }?.let { record ->
                    record.touched=now();record.value=record.value.copy(failures=record.value.failures+1,lastLatencyMs=(now()-start).coerceAtLeast(0),lastError=classify(error))
                }
            }
            throw error
        }
    }
    @Synchronized fun list(p: HomePrincipal): List<ProviderHealth> {
        prune();return health.entries.filter { it.key.principal==p }.map { it.value.value }.sortedByDescending { it.lastAttemptAt }
    }
    @Synchronized fun clear(p: HomePrincipal) {
        generations.remove(p)
        cache.keys.filter { it.principal==p }.toList().forEach(::remove)
        health.keys.removeIf { it.principal==p }
    }
    @TransactionalEventListener @Synchronized fun revoked(event: DeviceRevoked) {
        generations.keys.removeIf { it.deviceId==event.deviceId }
        cache.keys.filter { it.principal.deviceId==event.deviceId }.toList().forEach(::remove)
        health.keys.removeIf { it.principal.deviceId==event.deviceId }
    }
    private fun record(key: HealthKey): Observed = health.getOrPut(key) {
        while(health.keys.count { it.principal==key.principal }>=32)health.remove(health.keys.first { it.principal==key.principal })
        while(health.size>=256)health.remove(health.keys.first())
        Observed(ProviderHealth(hash((key.source+key.site).toByteArray()).take(24),key.site,0,0,0,0,null,0,null),now())
    }
    private fun prune() {
        cache.entries.filter { it.value.expires<=now() }.map { it.key }.forEach(::remove)
        health.entries.removeIf { now()-it.value.touched>=86_400_000 }
        val retained=health.keys.map { it.principal }.toSet()+cache.keys.map { it.principal }.toSet()
        generations.keys.retainAll(retained)
    }
    private fun remove(key: CacheKey) { cache.remove(key)?.let { bytes-=it.bytes.size } }
    private fun hash(value: ByteArray)=MessageDigest.getInstance("SHA-256").digest(value).joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun classify(error: Exception)=when((error as? ResponseStatusException)?.statusCode?.value()) {
        400,404->"invalid-request-or-result";401,403->"upstream-auth";408,504->"timeout";422->"unsupported-provider";429->"throttled";502,503->"upstream-failure";else->"request-failed"
    }
}

@RestController
@RequestMapping("/api/v1/home/providers")
class ProviderHealthController(private val accounts: HomeAccounts,private val gateway: ProviderGateway) {
    @GetMapping("/health") fun health(@RequestHeader("Authorization",required=false) auth: String?)=gateway.list(accounts.principal(auth))
    @PostMapping("/clear") fun clear(@RequestHeader("Authorization",required=false) auth: String?): Map<String,Boolean> { gateway.clear(accounts.principal(auth));return mapOf("cleared" to true) }
}
