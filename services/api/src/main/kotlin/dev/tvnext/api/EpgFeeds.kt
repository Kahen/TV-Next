package dev.tvnext.api

import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.scheduling.annotation.EnableScheduling
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class EpgFeedWrite(val name: String = "", val url: String = "", val intervalMinutes: Int = 360, val enabled: Boolean = true)
data class EpgFeedStatus(val id: String, val name: String, val url: String, val intervalMinutes: Int, val enabled: Boolean,
    val updatedAt: Long, val nextRefresh: Long, val lastError: String?, val available: Boolean)
data class EpgFeedGuideRequest(val channels: List<EpgChannelRequest> = emptyList(), val at: String? = null, val hours: Int = 12)

@Configuration
@EnableScheduling
class EpgScheduling

/** Persistent per-account feeds. Fetches share the pinned-address metadata transport and never use caller-supplied headers. */
@Service
class EpgFeeds(private val db: JdbcTemplate, private val transport: ProviderTransport, private val xmltv: XmltvGuideService) {
    private val refreshing = AtomicBoolean(false)
    private fun now() = System.currentTimeMillis()
    fun list(user: String): List<EpgFeedStatus> = db.query(
        "SELECT id,name,url,interval_minutes,enabled,updated_at,next_refresh,last_error,CASE WHEN content IS NULL THEN FALSE ELSE TRUE END FROM epg_feeds WHERE user_id=? ORDER BY name,id",
        { rs,_ -> EpgFeedStatus(rs.getString(1),rs.getString(2),rs.getString(3),rs.getInt(4),rs.getBoolean(5),rs.getLong(6),rs.getLong(7),rs.getString(8),rs.getBoolean(9)) },user)

    @Transactional
    fun create(user: String, r: EpgFeedWrite): EpgFeedStatus {
        if (r.name.isBlank() || r.name.length>80 || r.name.any { it.code<32 } || r.intervalMinutes !in 15..1440)
            fail(HttpStatus.BAD_REQUEST,"Invalid EPG feed name or refresh interval (15..1440 minutes)")
        Subscriptions.httpUri(r.url)
        // Serialize creates globally to keep the scheduled-fetch and storage budgets finite.
        db.queryForObject("SELECT version FROM epg_budget WHERE id=1 FOR UPDATE",Int::class.java)
        val total = db.queryForObject("SELECT COUNT(*) FROM epg_feeds",Int::class.java) ?: 0
        if (total>=200 || list(user).size>=10) fail(HttpStatus.CONFLICT,"EPG feed quota reached")
        val id=UUID.randomUUID().toString()
        db.update("INSERT INTO epg_feeds(id,user_id,name,url,interval_minutes,enabled) VALUES(?,?,?,?,?,?)",id,user,r.name.trim(),r.url,r.intervalMinutes,r.enabled)
        return list(user).first { it.id==id }
    }
    fun remove(user: String,id: String): Map<String,Boolean> {
        if(db.update("DELETE FROM epg_feeds WHERE user_id=? AND id=?",user,id)!=1) fail(HttpStatus.NOT_FOUND,"Unknown EPG feed")
        return mapOf("deleted" to true)
    }
    fun guide(user: String,id: String,r: EpgFeedGuideRequest): EpgGuideResponse {
        val xml=db.query("SELECT content FROM epg_feeds WHERE user_id=? AND id=?",{rs,_->rs.getString(1)},user,id).firstOrNull()
            ?: fail(HttpStatus.NOT_FOUND,"EPG feed has no downloaded guide; refresh it first")
        return xmltv.guide(EpgGuideRequest(xml,r.channels,r.at,r.hours))
    }
    fun refresh(user: String,id: String): EpgFeedStatus {
        val feed=list(user).firstOrNull { it.id==id } ?: fail(HttpStatus.NOT_FOUND,"Unknown EPG feed")
        if(!refreshing.compareAndSet(false,true)) fail(HttpStatus.TOO_MANY_REQUESTS,"An EPG refresh is already running")
        try {
            // Atomic lease also limits manual retries across API instances. Failures retain the old cache.
            if(!fetch(feed,user)) fail(HttpStatus.TOO_MANY_REQUESTS,"Wait at least one minute between EPG refresh attempts")
            return list(user).firstOrNull { it.id==id } ?: fail(HttpStatus.NOT_FOUND,"EPG feed was removed")
        } finally { refreshing.set(false) }
    }
    @Scheduled(fixedDelayString="\${TV_NEXT_EPG_TICK_MS:60000}",initialDelayString="\${TV_NEXT_EPG_INITIAL_DELAY_MS:60000}")
    fun refreshDue() {
        if(!refreshing.compareAndSet(false,true)) return
        try {
            val current=now()
            // No persistent background access for accounts with no live authorized devices.
            val users=db.query("SELECT DISTINCT f.user_id FROM epg_feeds f WHERE f.enabled=TRUE AND f.next_refresh<=? AND EXISTS (SELECT 1 FROM devices d WHERE d.user_id=f.user_id AND d.revoked=FALSE AND d.expires_at>?)",{rs,_->rs.getString(1)},current,current)
            users.forEach { user -> list(user).filter { it.enabled && it.nextRefresh<=current }.forEach { fetch(it,user) } }
        } finally { refreshing.set(false) }
    }
    private fun fetch(feed: EpgFeedStatus,user: String): Boolean {
        val start=now()
        // next_refresh doubles as a one-minute cross-process lease; compare the previous value.
        if(db.update("UPDATE epg_feeds SET next_refresh=?,last_attempt=? WHERE user_id=? AND id=? AND next_refresh=? AND last_attempt<=?",
            start+60_000,start,user,feed.id,feed.nextRefresh,start-60_000)!=1) return false
        val next=start+feed.intervalMinutes*60_000L
        try {
            val xml=transport.get(Subscriptions.httpUri(feed.url))
            xmltv.validate(xml)
            db.update("UPDATE epg_feeds SET content=?,updated_at=?,next_refresh=?,last_error=NULL WHERE user_id=? AND id=? AND next_refresh=?",xml,start,next,user,feed.id,start+60_000)
        } catch (_: Exception) {
            db.update("UPDATE epg_feeds SET next_refresh=?,last_error=? WHERE user_id=? AND id=? AND next_refresh=?",next,"Guide refresh failed; previous cache retained",user,feed.id,start+60_000)
        }
        return true
    }
    private fun fail(code: HttpStatus,message: String): Nothing = throw ResponseStatusException(code,message)
}

@RestController
@RequestMapping("/api/v1/home/epg/feeds")
class EpgFeedController(private val accounts: HomeAccounts,private val feeds: EpgFeeds) {
    private fun user(auth: String?)=accounts.principal(auth).userId
    @GetMapping fun list(@RequestHeader("Authorization",required=false) auth: String?)=feeds.list(user(auth))
    @PostMapping fun create(@RequestHeader("Authorization",required=false) auth: String?,@RequestBody r: EpgFeedWrite)=feeds.create(user(auth),r)
    @PostMapping("/{id}/remove") fun remove(@RequestHeader("Authorization",required=false) auth: String?,@PathVariable id: String)=feeds.remove(user(auth),id)
    @PostMapping("/{id}/refresh") fun refresh(@RequestHeader("Authorization",required=false) auth: String?,@PathVariable id: String)=feeds.refresh(user(auth),id)
    @PostMapping("/{id}/guide") fun guide(@RequestHeader("Authorization",required=false) auth: String?,@PathVariable id: String,@RequestBody r: EpgFeedGuideRequest)=feeds.guide(user(auth),id,r)
}
