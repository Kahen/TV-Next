package dev.tvnext.api
import com.fasterxml.jackson.databind.ObjectMapper
import java.net.URI
import java.net.http.HttpClient
import java.net.http.WebSocket
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import kotlin.test.*
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.web.server.ResponseStatusException

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties=["spring.datasource.url=\${TV_NEXT_TEST_DB_URL:jdbc:h2:mem:remote-tests;DB_CLOSE_DELAY=-1}","TV_NEXT_REGISTRATION_OPEN=true"])
class RemoteControlIntegrationTest @Autowired constructor(private val accounts:HomeAccounts,private val remote:RemoteControl,private val mapper:ObjectMapper) {
    @LocalServerPort private var port=0
    private fun user()=accounts.register(Credentials("remote-"+UUID.randomUUID(),"long-test-password","Controller"))
    private fun principal(s:HomeSession)=accounts.principal("Bearer "+s.token)
    @Test fun oneUseTicketsDeliverOnlyToAuthorizedDeviceAndAcknowledgeActions() {
        val owner=user();val p=principal(owner)
        val receiver=accounts.claim(PairingRequest("Receiver",accounts.pairing(p).code));val q=principal(receiver)
        val ticket=remote.ticket(q)
        val received=CompletableFuture<String>()
        val listener=object:WebSocket.Listener {
            override fun onOpen(socket:WebSocket){socket.request(1)}
            override fun onText(socket:WebSocket,data:CharSequence,last:Boolean):java.util.concurrent.CompletionStage<*>? { received.complete(data.toString());socket.request(1);return null }
        }
        HttpClient.newHttpClient().use { client ->
            val address=URI("ws://127.0.0.1:$port/api/v1/home/remote/socket?ticket=${ticket.ticket}")
            val socket=client.newWebSocketBuilder().buildAsync(address,listener).get(5,TimeUnit.SECONDS)
            try {
                val status=remote.send(p,RemoteRequest(receiver.device.id,"SEEK",45.0))
                val packet=mapper.readTree(received.get(5,TimeUnit.SECONDS))
                assertEquals(status.id,packet.path("id").asText());assertEquals(45.0,packet.path("position").asDouble())
                socket.sendText("""{"type":"ACK","id":"${status.id}","success":true}""",true).get(3,TimeUnit.SECONDS)
                org.awaitility.Awaitility.await().atMost(3,TimeUnit.SECONDS).until { remote.status(p,status.id).state=="acknowledged" }
                assertFails { client.newWebSocketBuilder().buildAsync(address,listener).get(3,TimeUnit.SECONDS) }
                val outsider=principal(user())
                assertFailsWith<ResponseStatusException> { remote.status(outsider,status.id) }
                assertFailsWith<ResponseStatusException> { remote.send(outsider,RemoteRequest(receiver.device.id,"PAUSE")) }
                accounts.revoke(p,receiver.device.id)
                assertFailsWith<ResponseStatusException> { remote.send(p,RemoteRequest(receiver.device.id,"PLAY")) }
            } finally { socket.abort() }
        }
    }
    @Test fun rejectsOfflineDevicesBadSeekAndUnsupportedMediaProtocols() {
        val user=user();val p=principal(user)
        assertEquals(409,assertFailsWith<ResponseStatusException> { remote.send(p,RemoteRequest(user.device.id,"PLAY")) }.statusCode.value())
        assertEquals(400,assertFailsWith<ResponseStatusException> { remote.send(p,RemoteRequest(user.device.id,"SEEK",Double.NaN)) }.statusCode.value())
        assertEquals(400,assertFailsWith<ResponseStatusException> { remote.send(p,RemoteRequest(user.device.id,"LOAD",url="javascript:alert(1)")) }.statusCode.value())
    }
}
