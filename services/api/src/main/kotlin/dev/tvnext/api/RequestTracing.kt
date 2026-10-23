package dev.tvnext.api
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import java.util.UUID
import org.slf4j.LoggerFactory
import org.slf4j.MDC
import org.springframework.core.annotation.Order
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import org.springframework.web.servlet.HandlerMapping

/** Record route templates, never query strings, request bodies, bearer tokens, pairing codes or media URLs. */
@Component
@Order(0)
class RequestTracing:OncePerRequestFilter() {
    private val log=LoggerFactory.getLogger(javaClass)
    override fun doFilterInternal(request:HttpServletRequest,response:HttpServletResponse,chain:FilterChain) {
        if(!request.requestURI.startsWith("/api/")){chain.doFilter(request,response);return}
        val id=UUID.randomUUID().toString();val start=System.nanoTime()
        response.setHeader("X-Request-Id",id);MDC.put("requestId",id)
        var failed=false
        try { chain.doFilter(request,response) } catch(error:Exception){failed=true;throw error}
        finally {
            val route=request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE)?.toString() ?: "unmatched"
            log.atInfo().addKeyValue("requestId",id).addKeyValue("method",request.method).addKeyValue("route",route)
                .addKeyValue("status",if(failed && response.status<400)500 else response.status).addKeyValue("durationMs",(System.nanoTime()-start)/1_000_000).log("http_request")
            MDC.remove("requestId")
        }
    }
}
