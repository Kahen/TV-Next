package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import java.net.URI
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class SyncedLibrary(val revision: Long, val updatedAt: Long, val library: JsonNode)
data class SaveLibraryRequest(val expectedRevision: Long = -1, val library: JsonNode? = null)

/** Same version-1 library shape on Web/iOS; compare-and-set rejects concurrent overwrite. */
@Service
class LibrarySync(private val db: JdbcTemplate, private val mapper: ObjectMapper) {
    fun read(p: HomePrincipal): SyncedLibrary = db.query("SELECT revision,updated_at,content FROM user_library WHERE user_id=?",
        { rs,_ -> SyncedLibrary(rs.getLong(1),rs.getLong(2),mapper.readTree(rs.getString(3))) },p.userId).firstOrNull()
        ?: fail(HttpStatus.NOT_FOUND,"Library not found")
    @Transactional
    fun save(p: HomePrincipal, request: SaveLibraryRequest): SyncedLibrary {
        if (request.expectedRevision < 0 || request.expectedRevision == Long.MAX_VALUE) fail(HttpStatus.BAD_REQUEST,"Invalid expectedRevision")
        val data=normalize(request.library)
        val text=mapper.writeValueAsString(data)
        if (text.toByteArray(Charsets.UTF_8).size>2_000_000) fail(HttpStatus.PAYLOAD_TOO_LARGE,"Library exceeds 2 MB")
        val next=request.expectedRevision+1; val now=System.currentTimeMillis()
        val affected=db.update("UPDATE user_library SET revision=?,content=?,updated_at=? WHERE user_id=? AND revision=?",
            next,text,now,p.userId,request.expectedRevision)
        if (affected!=1) fail(HttpStatus.CONFLICT,"Library changed on another device; fetch the latest revision before saving")
        return SyncedLibrary(next,now,data)
    }
    internal fun normalize(raw: JsonNode?): ObjectNode {
        if (raw==null || !raw.isObject || raw.path("version").asInt()!=1 ||
            !raw.path("channels").isArray || !raw.path("favorites").isArray || !raw.path("recent").isArray || !raw.path("positions").isObject)
            fail(HttpStatus.BAD_REQUEST,"Expected a version-1 library snapshot")
        if (raw.path("channels").size()>1500 || raw.path("favorites").size()>300 || raw.path("recent").size()>100 || raw.path("positions").size()>250)
            fail(HttpStatus.BAD_REQUEST,"Library collection exceeds limits")
        if (mapper.writeValueAsBytes(raw).size>2_000_000) fail(HttpStatus.PAYLOAD_TOO_LARGE,"Library exceeds 2 MB")
        val result=mapper.createObjectNode().put("version",1)
        val channels=result.putArray("channels"); val seen=mutableSetOf<String>()
        raw.path("channels").forEach { entry ->
            val channel=channel(entry)
            if (seen.add(channel.path("url").asText())) channels.add(channel)
        }
        val favorites=result.putArray("favorites");val favoriteUrls=mutableSetOf<String>()
        raw.path("favorites").forEach { entry ->
            if (!entry.isTextual || !mediaUrl(entry.asText())) fail(HttpStatus.BAD_REQUEST,"Invalid favorite URL")
            if (favoriteUrls.add(entry.asText())) favorites.add(entry.asText())
        }
        val recent=result.putArray("recent");val recentUrls=mutableSetOf<String>()
        raw.path("recent").forEach { entry ->
            val channel=channel(entry.path("channel"));val time=entry.path("openedAt")
            if (!time.isNumber || !time.asDouble().isFinite() || time.asDouble()<0 || time.asDouble()>9_000_000_000_000_000)
                fail(HttpStatus.BAD_REQUEST,"Invalid recent timestamp")
            if (recentUrls.add(channel.path("url").asText())) {
                val entry=recent.addObject();entry.set<JsonNode>("channel",channel);entry.put("openedAt",time.asLong())
            }
        }
        val positions=result.putObject("positions")
        raw.path("positions").fields().forEach { (url,time) ->
            if (!mediaUrl(url) || !time.isNumber || !time.asDouble().isFinite() || time.asDouble()<0 || time.asDouble()>=604800)
                fail(HttpStatus.BAD_REQUEST,"Invalid playback position")
            positions.put(url,time.asDouble())
        }
        return result
    }
    private fun channel(raw: JsonNode): ObjectNode {
        val url=raw.path("url").asText("")
        if (!raw.isObject || !mediaUrl(url) || !raw.path("name").isTextual || !raw.path("group").isTextual ||
            raw.path("name").asText().length>200 || raw.path("group").asText().length>100) fail(HttpStatus.BAD_REQUEST,"Invalid channel")
        val out=mapper.createObjectNode().put("name",raw.path("name").asText()).put("url",url).put("group",raw.path("group").asText())
        raw.path("logo").takeIf { it.isTextual && mediaUrl(it.asText()) }?.let { out.put("logo",it.asText()) }
        raw.path("tvgId").takeIf { it.isTextual }?.let { out.put("tvgId",it.asText().take(150)) }
        // Never upload access cookies, bearer tokens, or arbitrary playback header maps.
        val safe=out.putObject("headers");var omitted=raw.path("headersRequired").asBoolean(false)
        raw.path("headers").takeIf { it.isObject }?.fields()?.forEach { (key,value) ->
            if (key.lowercase() in setOf("user-agent","referer","origin") && value.isTextual && value.asText().length<=8192 && !value.asText().any { it.code<32 || it.code==127 })
                safe.put(key,value.asText())
            else omitted=true
        }
        if (omitted) out.put("headersRequired",true)
        return out
    }
    private fun mediaUrl(value: String): Boolean {
        if (value.length>2048 || value.isBlank() || value!=value.trim() || value.any { it.code<32 || it.code==127 }) return false
        val uri=runCatching { URI(value) }.getOrNull() ?: return false
        return uri.scheme?.lowercase() in setOf("http","https") && !uri.host.isNullOrBlank() && uri.rawUserInfo==null
    }
    private fun fail(status: HttpStatus,message: String): Nothing = throw ResponseStatusException(status,message)
}
@RestController
@RequestMapping("/api/v1/home/library")
class LibrarySyncController(private val accounts: HomeAccounts, private val library: LibrarySync) {
    @GetMapping fun read(@RequestHeader("Authorization",required=false) auth: String?)=library.read(accounts.principal(auth))
    @PostMapping fun save(@RequestHeader("Authorization",required=false) auth: String?,@RequestBody request: SaveLibraryRequest)=library.save(accounts.principal(auth),request)
}
