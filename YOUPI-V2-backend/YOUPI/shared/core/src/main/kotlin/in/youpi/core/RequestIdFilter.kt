package `in`.youpi.core

import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.http.server.reactive.ServerHttpResponse
import org.springframework.stereotype.Component
import org.springframework.web.server.ServerWebExchange
import org.springframework.web.server.WebFilter
import org.springframework.web.server.WebFilterChain
import reactor.core.publisher.Mono
import java.util.UUID

/**
 * Generates a unique request ID for every incoming request.
 * Stores it in the Reactor Context (NOT ThreadLocal — this is reactive).
 * Adds X-Request-ID to all responses for correlation.
 */
@Component
class RequestIdFilter : WebFilter {

    private val log = LoggerFactory.getLogger(javaClass)

    override fun filter(exchange: ServerWebExchange, chain: WebFilterChain): Mono<Void> {
        val incomingId = exchange.request.headers.getFirst("X-Request-ID")
        val requestId = incomingId ?: UUID.randomUUID().toString()

        // Add to exchange attributes for downstream use
        exchange.attributes["requestId"] = requestId

        // Add to response headers
        exchange.response.headers.set("X-Request-ID", requestId)

        // Also check for Cloud Trace header propagation
        val traceHeader = exchange.request.headers.getFirst("X-Cloud-Trace-Context")
        if (traceHeader != null) {
            exchange.attributes["traceContext"] = traceHeader
        }

        return chain.filter(exchange)
            .contextWrite { ctx ->
                ctx.put("requestId", requestId)
            }
    }
}
