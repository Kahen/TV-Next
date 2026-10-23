package dev.tvnext.api
import org.springframework.web.bind.annotation.*
data class ResourceRequest(val url: String = "")
@RestController
@RequestMapping("/api/v1/resources")
class TextResourceController(private val transport: ProviderTransport) {
    @PostMapping("/text") fun text(@RequestBody request: ResourceRequest) = mapOf("content" to transport.get(Subscriptions.httpUri(request.url)))
}
