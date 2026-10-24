package dev.tvnext.api

import jakarta.servlet.http.HttpServletResponse
import java.io.IOException
import java.io.PushbackInputStream
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets.UTF_8
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Service
import org.springframework.transaction.event.TransactionalEventListener
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class MediaRelayRequest(val url: String="",val headers: Map<String,String> = emptyMap())
data class MediaRelaySession(val path: String,val expiresAt: Long)

/** URLs are short-lived capabilities for an already registered resource, never an arbitrary forwarding endpoint. */
@Service
class MediaRelay(private val accounts: HomeAccounts,private val transport: MediaTransport) {
    private class Session(val principal: HomePrincipal,val headers: Map<String,String>,val origin: String,val expires: Long) {
        val resources=linkedMapOf("0" to URI("https://invalid.invalid"))
        @Volatile var touched=System.currentTimeMillis();var transferred=0L;var requests=0;var minute=0L
        var resourceBytes=0
        val streams=mutableSetOf<MediaResponse>()
        @Volatile var closed=false
    }
    private val sessions=ConcurrentHashMap<String,Session>()
    private val permits=Semaphore(4)
    @Synchronized fun create(p: HomePrincipal,r: MediaRelayRequest): MediaRelaySession {
        val uri=Subscriptions.httpUri(r.url)
        ProviderTransport.validateHeaders(r.headers)
        if(r.headers.keys.any { it.lowercase() in setOf("range","if-range","accept","if-none-match","if-modified-since") })
            reject(HttpStatus.BAD_REQUEST,"Media range and cache headers are managed by the relay")
        val now=System.currentTimeMillis()
        sessions.entries.toList().filter { expired(it.value,now) }.forEach { remove(it.key,it.value) }
        val deviceSessions=sessions.entries.filter { it.value.principal.deviceId==p.deviceId }.sortedBy { it.value.touched }
        if(deviceSessions.size>=4)deviceSessions.take(deviceSessions.size-3).forEach { remove(it.key,it.value) }
        if(sessions.size>=128)reject(HttpStatus.TOO_MANY_REQUESTS,"Media session limit; stop an old player")
        val ticket=Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) })
        val session=Session(p,r.headers.toMap(),mediaOrigin(uri),now+6*60*60*1000L)
        session.resources["0"]=uri;session.resourceBytes=uri.toString().toByteArray(UTF_8).size;sessions[hash(ticket)]=session
        return MediaRelaySession("/api/v1/home/media/$ticket/0",session.expires)
    }
    fun close(p: HomePrincipal,ticket: String) {
        val key=key(ticket);val session=sessions[key] ?: return
        if(session.principal!=p)reject(HttpStatus.NOT_FOUND,"Unknown media session")
        remove(key,session)
    }
    @TransactionalEventListener fun revoked(event: DeviceRevoked) {
        sessions.entries.toList().filter { it.value.principal.deviceId==event.deviceId }.forEach { remove(it.key,it.value) }
    }
    private fun remove(key: String,session: Session) {
        sessions.remove(key,session)
        synchronized(session) { session.closed=true;session.streams.toList().forEach { runCatching { it.close() } };session.resources.clear() }
    }
    private fun expired(s: Session,now: Long)=s.closed || now>=s.expires || now-s.touched>=30*60*1000L
    private fun active(s: Session) {
        if(expired(s,System.currentTimeMillis()) || accounts.devices(s.principal).none { it.id==s.principal.deviceId })
            reject(HttpStatus.UNAUTHORIZED,"Media session expired or revoked")
    }
    fun serve(ticket: String,resource: String,range: String?,head: Boolean,response: HttpServletResponse) {
        val s=sessions[key(ticket)] ?: reject(HttpStatus.UNAUTHORIZED,"Media session expired or revoked")
        active(s)
        val uri=synchronized(s) {
            val now=System.currentTimeMillis();val minute=now/60000
            if(s.minute!=minute){s.minute=minute;s.requests=0}
            if(++s.requests>240)reject(HttpStatus.TOO_MANY_REQUESTS,"Media session rate limit")
            s.touched=now
            s.resources[resource] ?: reject(HttpStatus.NOT_FOUND,"Unknown media resource")
        }
        if(!permits.tryAcquire())reject(HttpStatus.TOO_MANY_REQUESTS,"Media connection limit")
        try {
            val bounded=MediaTransport.boundedRange(range)
            val headers=if(mediaOrigin(uri)==s.origin)s.headers else emptyMap()
            transport.fetch(uri,headers,if(uri.path.lowercase().endsWith(".m3u8"))null else bounded,head).use { upstream ->
                synchronized(s) { active(s);s.streams+=upstream }
                try {
                    response.setHeader("Cache-Control","no-store, private")
                    response.setHeader("Referrer-Policy","no-referrer")
                    response.setHeader("X-Content-Type-Options","nosniff")
                    response.setHeader("Content-Security-Policy","default-src 'none'; sandbox")
                    if(upstream.status==416) {
                        response.status=416
                        upstream.headers["content-range"]?.takeIf { Regex("bytes \\*/[0-9]{1,16}").matches(it) }?.let { response.setHeader("Content-Range",it) }
                        return
                    }
                    val mime=upstream.headers["content-type"].orEmpty().substringBefore(';').lowercase()
                    val input=PushbackInputStream(upstream.body,16)
                    val prefix=if(head)byteArrayOf() else input.readNBytes(16).also { input.unread(it) }
                    val manifest=String(prefix,UTF_8).removePrefix("\uFEFF").startsWith("#EXTM3U") || mime in setOf("application/vnd.apple.mpegurl","application/x-mpegurl","audio/mpegurl","audio/x-mpegurl") || upstream.uri.path.lowercase().endsWith(".m3u8")
                    if(manifest && !head) {
                        if(upstream.status!=200)reject(HttpStatus.BAD_GATEWAY,"Partial HLS playlists are unsupported")
                        val bytes=input.readNBytes(1_048_577)
                        if(bytes.size>1_048_576)reject(HttpStatus.BAD_GATEWAY,"HLS playlist limit")
                        charge(s,bytes.size)
                        val text=runCatching { UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString() }.getOrElse { reject(HttpStatus.BAD_GATEWAY,"HLS must be UTF-8") }
                        val body=rewrite(text,upstream.uri) { child -> register(s,ticket,child) }.toByteArray(UTF_8)
                        response.contentType="application/vnd.apple.mpegurl";response.setContentLength(body.size)
                        response.outputStream.write(body);return
                    }
                    if(!manifest && !(mime=="text/vtt" && resource!="0") && !mime.startsWith("video/") && !mime.startsWith("audio/") && mime !in setOf("application/octet-stream","application/mp4","application/mp2t","binary/octet-stream",""))
                        reject(HttpStatus.BAD_GATEWAY,"Upstream is not a supported media resource")
                    response.status=upstream.status
                    response.contentType=if(manifest)"application/vnd.apple.mpegurl" else mime.ifEmpty { "application/octet-stream" }
                    listOf("content-length","content-range","accept-ranges").forEach { name ->
                        if(!(manifest && name=="content-length"))upstream.headers[name]?.let { response.setHeader(name,it) }
                    }
                    if(head)return
                    val buffer=ByteArray(65536)
                    while(true) {
                        val count=input.read(buffer);if(count<0)break
                        charge(s,count)
                        response.outputStream.write(buffer,0,count)
                    }
                } finally { synchronized(s) { s.streams-=upstream } }
            }
        } catch(error: ResponseStatusException) { if(response.isCommitted)throw IOException("Media transfer interrupted");throw error }
        catch(error: IOException) { if(!response.isCommitted)reject(HttpStatus.BAD_GATEWAY,"Media transfer failed");throw IOException("Media transfer interrupted") }
        finally { permits.release() }
    }
    private fun charge(s: Session,count: Int) = synchronized(s) {
        if(expired(s,System.currentTimeMillis()) || s.transferred+count>4_294_967_296L)reject(HttpStatus.TOO_MANY_REQUESTS,"Media session transfer quota or expiry")
        s.transferred+=count
    }
    private fun register(s: Session,ticket: String,uri: URI): String = synchronized(s) {
        if(s.closed)reject(HttpStatus.UNAUTHORIZED,"Media session revoked")
        val existing=s.resources.entries.firstOrNull { it.value==uri }?.key
        val id=existing ?: s.resources.size.toString().also {
            if(s.resources.size>=4096 || s.resourceBytes+uri.toString().toByteArray(UTF_8).size>524288)reject(HttpStatus.BAD_GATEWAY,"HLS resource limit")
            s.resourceBytes+=uri.toString().toByteArray(UTF_8).size
            s.resources[it]=uri
        }
        "/api/v1/home/media/$ticket/$id"
    }
    companion object {
        internal fun rewrite(text: String,base: URI,register: (URI)->String): String {
            if(!text.removePrefix("\uFEFF").startsWith("#EXTM3U"))reject(HttpStatus.BAD_GATEWAY,"Invalid HLS playlist")
            fun local(raw: String): String {
                if(raw.isEmpty() || raw.contains("{$") || raw.any { it.code<32 })reject(HttpStatus.BAD_GATEWAY,"Unsupported HLS resource")
                val uri=runCatching { Subscriptions.httpUri(base.resolve(raw).toString()) }.getOrElse { reject(HttpStatus.BAD_GATEWAY,"Unsupported HLS resource") }
                return register(uri)
            }
            return text.lineSequence().joinToString("\n") { line ->
                val trimmed=line.trim()
                if(trimmed.isEmpty())line else if(!trimmed.startsWith('#'))local(trimmed)
                else {
                    val pattern=Regex("(?<![A-Z0-9-])URI=\"([^\"]*)\"")
                    val rewritten=pattern.replace(line) { "URI=\"${local(it.groupValues[1])}\"" }
                    if(Regex("(?<![A-Z0-9-])URI=(?!\")").containsMatchIn(rewritten))reject(HttpStatus.BAD_GATEWAY,"Malformed HLS URI attribute")
                    rewritten
                }
            }
        }
        private fun key(ticket: String): String {
            if(!Regex("[A-Za-z0-9_-]{43}").matches(ticket))reject(HttpStatus.UNAUTHORIZED,"Invalid media session")
            return hash(ticket)
        }
        private fun hash(value: String)=MessageDigest.getInstance("SHA-256").digest(value.toByteArray(UTF_8)).joinToString("") { "%02x".format(it.toInt() and 255) }
        private fun reject(status: HttpStatus,message: String): Nothing = throw ResponseStatusException(status,message)
    }
}

@RestController
@RequestMapping("/api/v1/home/media")
class MediaRelayController(private val accounts: HomeAccounts,private val relay: MediaRelay) {
    @PostMapping("/sessions") fun create(@RequestHeader("Authorization",required=false) auth: String?,@RequestBody r: MediaRelayRequest)=relay.create(accounts.principal(auth),r)
    @PostMapping("/{ticket}/close") fun close(@RequestHeader("Authorization",required=false) auth: String?,@PathVariable ticket: String): Map<String,Boolean> { relay.close(accounts.principal(auth),ticket);return mapOf("closed" to true) }
    @RequestMapping("/{ticket}/{resource}",method=[RequestMethod.GET,RequestMethod.HEAD])
    fun get(@PathVariable ticket: String,@PathVariable resource: String,@RequestHeader("Range",required=false) range: String?,request: jakarta.servlet.http.HttpServletRequest,response: HttpServletResponse) = relay.serve(ticket,resource,range,request.method=="HEAD",response)
}
