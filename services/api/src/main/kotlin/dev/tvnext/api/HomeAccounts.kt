package dev.tvnext.api

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.Locale
import java.util.UUID
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.ApplicationEventPublisher
import org.springframework.dao.DuplicateKeyException
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException

data class Credentials(val username: String = "", val password: String = "", val deviceName: String = "Device")
data class HomeUser(val id: String, val username: String)
data class HomeDevice(val id: String, val name: String, val createdAt: Long, val expiresAt: Long, val current: Boolean = false)
data class HomeSession(val token: String, val user: HomeUser, val device: HomeDevice)
data class HomePrincipal(val userId: String, val deviceId: String)
data class PairingRequest(val deviceName: String = "Device", val code: String = "")
data class PairingCode(val code: String, val expiresAt: Long)
data class DeviceRevoked(val deviceId: String)

@Service
class HomeAccounts(private val db: JdbcTemplate, @Value("\${TV_NEXT_REGISTRATION_OPEN:false}") private val registrationOpen: Boolean,
    private val events: ApplicationEventPublisher) {
    private val random = SecureRandom()
    private val dummySalt = ByteArray(32).also { random.nextBytes(it) }
    private fun now() = System.currentTimeMillis()
    @Transactional
    fun register(r: Credentials): HomeSession {
        if (!registrationOpen) fail(HttpStatus.FORBIDDEN,"Registration is disabled by the server administrator")
        val name = username(r.username)
        if (r.password.length !in 12..128) fail(HttpStatus.BAD_REQUEST,"Password must be 12..128 characters")
        deviceName(r.deviceName)
        val salt = ByteArray(32).also { random.nextBytes(it) }
        val id = UUID.randomUUID().toString()
        try {
            db.update("INSERT INTO app_users(id,username,password_salt,password_hash,created_at) VALUES(?,?,?,?,?)",
                id,name,hex(salt),hex(passwordHash(r.password,salt)),now())
        } catch (_: DuplicateKeyException) { fail(HttpStatus.CONFLICT,"Username is unavailable") }
        db.update("INSERT INTO user_library(user_id,revision,content,updated_at) VALUES(?,?,?,?)",id,0L,
            """{"version":1,"channels":[],"favorites":[],"recent":[],"positions":{}}""",now())
        return issue(id,name,r.deviceName)
    }
    @Transactional
    fun login(r: Credentials): HomeSession {
        val name = username(r.username)
        if (r.password.length > 128) fail(HttpStatus.UNAUTHORIZED,"Invalid credentials")
        deviceName(r.deviceName)
        data class Account(val id: String, val salt: String, val hash: String, val iterations: Int)
        val user = db.query("SELECT id,password_salt,password_hash,password_iterations FROM app_users WHERE username=?", { rs,_ ->
            Account(rs.getString(1),rs.getString(2),rs.getString(3),rs.getInt(4)) }, name).firstOrNull()
        val actual = passwordHash(r.password,user?.salt?.let { unhex(it) } ?: dummySalt,user?.iterations ?: 600_000)
        if (user == null || !MessageDigest.isEqual(actual,unhex(user.hash))) fail(HttpStatus.UNAUTHORIZED,"Invalid credentials")
        return issue(user.id,name,r.deviceName,recover=true)
    }
    fun principal(authorization: String?): HomePrincipal {
        val token = authorization?.let { Regex("(?i)^Bearer ([A-Za-z0-9_-]{43})$").matchEntire(it)?.groupValues?.get(1) }
            ?: fail(HttpStatus.UNAUTHORIZED,"A device bearer token is required")
        return db.query("SELECT user_id,id FROM devices WHERE token_hash=? AND revoked=FALSE AND expires_at>?",
            { rs,_ -> HomePrincipal(rs.getString(1),rs.getString(2)) },sha(token),now()).firstOrNull()
            ?: fail(HttpStatus.UNAUTHORIZED,"Device token is expired or revoked")
    }
    fun devices(p: HomePrincipal): List<HomeDevice> = db.query(
        "SELECT id,name,created_at,expires_at FROM devices WHERE user_id=? AND revoked=FALSE AND expires_at>? ORDER BY created_at DESC",
        { rs,_ -> HomeDevice(rs.getString(1),rs.getString(2),rs.getLong(3),rs.getLong(4),rs.getString(1)==p.deviceId) },p.userId,now())
    @Transactional
    fun revoke(p: HomePrincipal, deviceId: String) {
        lockUser(p.userId)
        requireActive(p)
        if (db.update("UPDATE devices SET revoked=TRUE WHERE id=? AND user_id=?",deviceId,p.userId) != 1)
            fail(HttpStatus.NOT_FOUND,"Unknown device")
        db.update("DELETE FROM device_pairings WHERE creator_device=?",deviceId)
        events.publishEvent(DeviceRevoked(deviceId))
    }
    @Transactional
    fun pairing(p: HomePrincipal): PairingCode {
        lockUser(p.userId)
        requireActive(p)
        val current=now()
        db.update("DELETE FROM device_pairings WHERE expires_at<? OR used=TRUE",current)
        db.update("DELETE FROM device_pairings WHERE creator_device=?",p.deviceId)
        val code=hex(ByteArray(8).also { random.nextBytes(it) }).uppercase(Locale.ROOT)
        val expires=current+300_000L
        db.update("INSERT INTO device_pairings(code_hash,user_id,creator_device,expires_at,used) VALUES(?,?,?,?,FALSE)",sha(code),p.userId,p.deviceId,expires)
        return PairingCode(code.chunked(4).joinToString("-"),expires)
    }
    @Transactional
    fun claim(r: PairingRequest): HomeSession {
        deviceName(r.deviceName)
        if (r.code.length>64) fail(HttpStatus.UNAUTHORIZED,"Invalid or expired pairing code")
        val code=r.code.replace("-","").replace(" ","").uppercase(Locale.ROOT)
        if (!code.matches(Regex("[0-9A-F]{16}"))) fail(HttpStatus.UNAUTHORIZED,"Invalid or expired pairing code")
        val hash=sha(code)
        val user=db.query("SELECT user_id FROM device_pairings WHERE code_hash=?", { rs,_ -> rs.getString(1) },hash).firstOrNull()
            ?: fail(HttpStatus.UNAUTHORIZED,"Invalid or expired pairing code")
        lockUser(user)
        val owner=db.query("SELECT p.user_id,u.username FROM device_pairings p JOIN app_users u ON p.user_id=u.id JOIN devices d ON p.creator_device=d.id WHERE p.code_hash=? AND p.used=FALSE AND p.expires_at>? AND d.revoked=FALSE AND d.expires_at>?",
            { rs,_ -> HomeUser(rs.getString(1),rs.getString(2)) },hash,now(),now()).firstOrNull()
            ?: fail(HttpStatus.UNAUTHORIZED,"Invalid or expired pairing code")
        if (db.update("UPDATE device_pairings SET used=TRUE WHERE code_hash=? AND used=FALSE AND expires_at>?",hash,now()) != 1)
            fail(HttpStatus.UNAUTHORIZED,"Invalid or expired pairing code")
        return issue(owner.id,owner.username,r.deviceName)
    }
    private fun lockUser(user: String) {
        db.queryForObject("SELECT id FROM app_users WHERE id=? FOR UPDATE",String::class.java,user)
    }
    private fun requireActive(p: HomePrincipal) {
        val count=db.queryForObject("SELECT COUNT(*) FROM devices WHERE id=? AND user_id=? AND revoked=FALSE AND expires_at>?",Int::class.java,p.deviceId,p.userId,now()) ?: 0
        if(count!=1) fail(HttpStatus.UNAUTHORIZED,"Device token is expired or revoked")
    }
    private fun issue(user: String, username: String, name: String, recover: Boolean=false): HomeSession {
        lockUser(user)
        val count=db.queryForObject("SELECT COUNT(*) FROM devices WHERE user_id=? AND revoked=FALSE AND expires_at>?",Int::class.java,user,now()) ?: 0
        if (count>=50) {
            if(!recover) fail(HttpStatus.CONFLICT,"Device limit reached; sign in with your password to recover access")
            // Password authentication can recover an account even when all device slots are occupied.
            val oldest=db.query("SELECT id FROM devices WHERE user_id=? AND revoked=FALSE AND expires_at>? ORDER BY created_at,id", { rs,_ -> rs.getString(1) },user,now()).take(count-49)
            oldest.forEach { id ->
                db.update("UPDATE devices SET revoked=TRUE WHERE id=? AND user_id=?",id,user)
                db.update("DELETE FROM device_pairings WHERE creator_device=?",id)
                events.publishEvent(DeviceRevoked(id))
            }
        }
        val id=UUID.randomUUID().toString();val created=now();val expires=created+90L*24*60*60*1000
        val token=Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also { random.nextBytes(it) })
        db.update("INSERT INTO devices(id,user_id,name,token_hash,created_at,expires_at,revoked) VALUES(?,?,?,?,?,?,FALSE)",id,user,deviceName(name),sha(token),created,expires)
        return HomeSession(token,HomeUser(user,username),HomeDevice(id,name,created,expires,true))
    }
    private fun username(value: String): String {
        val result=value.trim().lowercase(Locale.ROOT)
        if (!result.matches(Regex("[a-z0-9_.@+-]{3,100}"))) fail(HttpStatus.BAD_REQUEST,"Username must be 3..100 ASCII characters")
        return result
    }
    private fun deviceName(value: String): String {
        if (value.isBlank() || value.length>80 || value.any { it.code<32 }) fail(HttpStatus.BAD_REQUEST,"Invalid device name")
        return value
    }
    private fun passwordHash(value: String, salt: ByteArray, iterations: Int = 600_000): ByteArray {
        val spec=PBEKeySpec(value.toCharArray(),salt,iterations,256)
        return try { SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded } finally { spec.clearPassword() }
    }
    private fun hex(value: ByteArray)=value.joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun unhex(value: String)=value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    private fun sha(value: String)=hex(MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)))
    private fun fail(status: HttpStatus,message: String): Nothing = throw ResponseStatusException(status,message)
}
@RestController
@RequestMapping("/api/v1/home")
class HomeAccountController(private val accounts: HomeAccounts) {
    @PostMapping("/auth/register") fun register(@RequestBody r: Credentials)=accounts.register(r)
    @PostMapping("/auth/login") fun login(@RequestBody r: Credentials)=accounts.login(r)
    @GetMapping("/devices") fun devices(@RequestHeader("Authorization",required=false) auth: String?)=accounts.devices(accounts.principal(auth))
    @PostMapping("/devices/{id}/revoke") fun revoke(@RequestHeader("Authorization",required=false) auth: String?,@PathVariable id: String): Map<String,Boolean> { accounts.revoke(accounts.principal(auth),id);return mapOf("revoked" to true) }
    @PostMapping("/pairings") fun pairing(@RequestHeader("Authorization",required=false) auth: String?)=accounts.pairing(accounts.principal(auth))
    @PostMapping("/pairings/claim") fun claim(@RequestBody r: PairingRequest)=accounts.claim(r)
}
