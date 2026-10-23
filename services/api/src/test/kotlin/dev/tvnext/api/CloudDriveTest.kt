package dev.tvnext.api
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.net.URI
import kotlin.test.*
import org.springframework.web.server.ResponseStatusException

class CloudDriveTest {
    private val mapper = jacksonObjectMapper()
    private class CloudTransport: ProviderTransport() {
        var answer = "{}"; var body = ""; var headers = emptyMap<String,String>(); var uri: URI? = null
        override fun postJson(uri: URI, headers: Map<String,String>, json: String): String { this.uri=uri;this.headers=headers;body=json;return answer }
    }
    @Test fun originalOpenListListAndGetShapesDoNotTreatPresentationHtmlAsHeaders() {
        val transport = CloudTransport()
        val cloud = CloudDrive(mapper,transport)
        transport.answer = """{"code":200,"data":{"content":[{"name":"Folder","is_dir":true,"size":0},{"name":"movie.mp4","is_dir":false,"size":123}],"total":150}}"""
        val page = cloud.list(CloudRequest(server="https://openlist.example/",token="own-token",path="/Movies"))
        assertTrue(page.hasMore);assertEquals(2,page.entries.size)
        assertEquals("https://openlist.example/api/fs/list",transport.uri.toString())
        assertEquals("own-token",transport.headers["Authorization"])
        assertEquals(100,mapper.readTree(transport.body).path("per_page").asInt())
        transport.answer = """{"code":200,"data":{"name":"movie.mp4","raw_url":"https://cdn.example/video.mp4?sign=own","header":"<h1>Presentation</h1>"}}"""
        val play = cloud.play(CloudRequest(server="https://openlist.example/",path="/Movies/movie.mp4"))
        assertTrue(play.headers.isEmpty());assertTrue(play.url.contains("sign=own"))
    }
    @Test fun rejectsTraversalMalformedServiceAndExpiredCredentials() {
        val transport = CloudTransport(); val cloud = CloudDrive(mapper,transport)
        assertFailsWith<ResponseStatusException> { cloud.list(CloudRequest(server="https://example.org/",path="/../secret")) }
        assertFailsWith<ResponseStatusException> { cloud.list(CloudRequest(server="https://user:secret@example.org/")) }
        transport.answer = """{"code":401,"message":"expired"}"""
        assertFailsWith<ResponseStatusException> { cloud.list(CloudRequest(server="https://example.org/")) }
    }
}
