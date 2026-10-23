package dev.tvnext.api

import com.fasterxml.jackson.databind.ObjectMapper
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import org.springframework.http.HttpStatus
import org.springframework.http.server.ServerHttpRequest
import org.springframework.http.server.ServerHttpResponse
import org.springframework.stereotype.Component
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException
import org.springframework.web.socket.*
import org.springframework.web.socket.config.annotation.*
import org.springframework.web.socket.handler.TextWebSocketHandler
import org.springframework.web.socket.server.HandshakeInterceptor
import org.springframework.context.annotation.Configuration
import org.springframework.transaction.event.TransactionalEventListener
import org.springframework.web.util.UriComponentsBuilder

data class RemoteTicket(val ticket: String, val expiresAt: Long)
data class RemoteRequest(val targetDeviceId: String="", val type: String="", val position: Double?=null, val url: String?=null)
data class RemotePacket(val id: String, val type: String, val position: Double?, val url: String?)
data class RemoteStatus(val id: String, val state: String, val message: String?=null)
data class RemoteDevice(val id: String,val name: String,val current: Boolean,val online: Boolean)

/** Ephemeral, per-device channels. Authentication tokens never appear in a WebSocket URL. */
@Component
class RemoteControl(private val accounts: HomeAccounts,private val mapper: ObjectMapper): TextWebSocketHandler(),HandshakeInterceptor {
    private data class Ticket(val principal: HomePrincipal,val expires: Long)
    private data class Connection(val principal: HomePrincipal,val socket: WebSocketSession)
    private data class Delivery(val owner: String,val device: String,val expires: Long,@Volatile var status: RemoteStatus)
    private val tickets=ConcurrentHashMap<String,Ticket>()
    private val connections=ConcurrentHashMap<String,Connection>()
    private val commands=ConcurrentHashMap<String,Delivery>()
    fun ticket(p: HomePrincipal): RemoteTicket {
        val now=System.currentTimeMillis();tickets.entries.removeIf { it.value.expires<=now }
        if(tickets.size>=512) reject(HttpStatus.TOO_MANY_REQUESTS,"Remote ticket limit")
        val value=Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) })
        tickets[hash(value)]=Ticket(p,now+30_000)
        return RemoteTicket(value,now+30_000)
    }
    fun devices(p: HomePrincipal)=accounts.devices(p).map { RemoteDevice(it.id,it.name,it.current,connections[it.id]?.socket?.isOpen==true) }
    fun send(p: HomePrincipal,r: RemoteRequest): RemoteStatus {
        if(r.type !in setOf("PLAY","PAUSE","SEEK","LOAD")) reject(HttpStatus.BAD_REQUEST,"Invalid remote action")
        if(r.type=="SEEK" && (r.position==null || !r.position.isFinite() || r.position<0 || r.position>=604800)) reject(HttpStatus.BAD_REQUEST,"Invalid seek position")
        if(r.type=="LOAD") Subscriptions.httpUri(r.url ?: reject(HttpStatus.BAD_REQUEST,"url required"))
        if(accounts.devices(p).none { it.id==r.targetDeviceId }) reject(HttpStatus.NOT_FOUND,"Unknown target device")
        val connection=connections[r.targetDeviceId]?.takeIf { it.principal.userId==p.userId && it.socket.isOpen }
            ?: reject(HttpStatus.CONFLICT,"Target device is offline")
        val now=System.currentTimeMillis();commands.entries.removeIf { it.value.expires<=now }
        if(commands.size>=1024) reject(HttpStatus.TOO_MANY_REQUESTS,"Remote command limit")
        val id=UUID.randomUUID().toString();val status=RemoteStatus(id,"dispatched")
        commands[id]=Delivery(p.userId,r.targetDeviceId,now+300_000,status)
        try { synchronized(connection.socket) { connection.socket.sendMessage(TextMessage(mapper.writeValueAsString(RemotePacket(id,r.type,if(r.type=="SEEK")r.position else null,if(r.type=="LOAD")r.url else null)))) } }
        catch(_:Exception){commands[id]?.status=RemoteStatus(id,"failed","Target connection closed");connections.remove(r.targetDeviceId,connection);runCatching { connection.socket.close() };reject(HttpStatus.CONFLICT,"Target connection closed")}
        return status
    }
    fun status(p: HomePrincipal,id: String): RemoteStatus = commands[id]?.takeIf { it.owner==p.userId && it.expires>System.currentTimeMillis() }?.status
        ?: reject(HttpStatus.NOT_FOUND,"Unknown or expired command")
    @TransactionalEventListener
    fun revoked(event: DeviceRevoked) { disconnect(event.deviceId) }
    fun disconnect(device: String) { connections.remove(device)?.socket?.let { runCatching { it.close(CloseStatus.NORMAL) } } }
    override fun beforeHandshake(request: ServerHttpRequest,response: ServerHttpResponse,handler: WebSocketHandler,attributes: MutableMap<String,Any>): Boolean {
        val raw=UriComponentsBuilder.fromUri(request.uri).build().queryParams.getFirst("ticket").orEmpty()
        val ticket=tickets.remove(hash(raw))
        if(raw.length!=43 || ticket==null || ticket.expires<=System.currentTimeMillis() || !active(ticket.principal)) { response.setStatusCode(HttpStatus.UNAUTHORIZED);return false }
        if(connections.size>=512 && !connections.containsKey(ticket.principal.deviceId)) { response.setStatusCode(HttpStatus.TOO_MANY_REQUESTS);return false }
        attributes["tvnext-principal"]=ticket.principal
        return true
    }
    override fun afterHandshake(request: ServerHttpRequest,response: ServerHttpResponse,handler: WebSocketHandler,exception: Exception?) {}
    override fun afterConnectionEstablished(session: WebSocketSession) {
        val principal=session.attributes["tvnext-principal"] as HomePrincipal
        if(!active(principal)){session.close(CloseStatus.POLICY_VIOLATION);return}
        session.textMessageSizeLimit=8192
        val old=connections.put(principal.deviceId,Connection(principal,session))
        if(old?.socket?.id!=session.id) old?.socket?.let { runCatching { it.close(CloseStatus.NORMAL) } }
        // Cover a revoke committed between the handshake check and registration.
        if(!active(principal)) {
            connections.computeIfPresent(principal.deviceId) { _,current -> if(current.socket.id==session.id)null else current }
            session.close(CloseStatus.POLICY_VIOLATION)
        }
    }
    override fun handleTextMessage(session: WebSocketSession,message: TextMessage) {
        synchronized(session) {
            val minute=System.currentTimeMillis()/60_000
            val start=session.attributes["tvnext-minute"] as? Long
            val count=if(start==minute)(session.attributes["tvnext-count"] as? Int ?: 0)+1 else 1
            session.attributes["tvnext-minute"]=minute;session.attributes["tvnext-count"]=count
            if(count>120){session.close(CloseStatus.POLICY_VIOLATION);return}
        }
        val p=session.attributes["tvnext-principal"] as HomePrincipal
        if(!active(p)){session.close(CloseStatus.POLICY_VIOLATION);return}
        val node=runCatching { mapper.readTree(message.payload) }.getOrNull() ?: return
        if(node.path("type").asText()=="PING") { synchronized(session) { session.sendMessage(TextMessage("{\"type\":\"PONG\"}")) };return }
        if(node.path("type").asText()!="ACK")return
        val id=node.path("id").asText();val delivery=commands[id] ?: return
        if(delivery.owner!=p.userId || delivery.device!=p.deviceId || delivery.expires<=System.currentTimeMillis())return
        if(delivery.status.state!="dispatched")return
        delivery.status=RemoteStatus(id,if(node.path("success").asBoolean())"acknowledged" else "rejected",node.path("message").asText("").take(200).ifBlank { null })
    }
    override fun afterConnectionClosed(session: WebSocketSession,status: CloseStatus) {
        val p=session.attributes["tvnext-principal"] as? HomePrincipal ?: return
        connections.computeIfPresent(p.deviceId) { _,connection -> if(connection.socket.id==session.id)null else connection }
    }
    override fun handleTransportError(session: WebSocketSession,exception: Throwable) { runCatching { session.close(CloseStatus.SERVER_ERROR) } }
    private fun active(p: HomePrincipal)=accounts.devices(p).any { it.id==p.deviceId }
    private fun hash(value:String)=MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun reject(status:HttpStatus,message:String):Nothing=throw ResponseStatusException(status,message)
}
@Configuration
@EnableWebSocket
class RemoteSocketConfiguration(private val remote: RemoteControl):WebSocketConfigurer {
    override fun registerWebSocketHandlers(registry: WebSocketHandlerRegistry) {
        val allowed=System.getenv("TV_NEXT_CORS_ALLOWED_ORIGINS")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: listOf("http://localhost:5173","http://127.0.0.1:5173","http://localhost:3000","http://127.0.0.1:3000")
        registry.addHandler(remote,"/api/v1/home/remote/socket").addInterceptors(remote).setAllowedOrigins(*allowed.toTypedArray())
    }
}
@RestController
@RequestMapping("/api/v1/home/remote")
class RemoteController(private val accounts: HomeAccounts,private val remote: RemoteControl) {
    @PostMapping("/ticket") fun ticket(@RequestHeader("Authorization",required=false) auth:String?)=remote.ticket(accounts.principal(auth))
    @GetMapping("/devices") fun devices(@RequestHeader("Authorization",required=false) auth:String?)=remote.devices(accounts.principal(auth))
    @PostMapping("/commands") fun command(@RequestHeader("Authorization",required=false) auth:String?,@RequestBody r:RemoteRequest)=remote.send(accounts.principal(auth),r)
    @GetMapping("/commands/{id}") fun status(@RequestHeader("Authorization",required=false) auth:String?,@PathVariable id:String)=remote.status(accounts.principal(auth),id)
}
