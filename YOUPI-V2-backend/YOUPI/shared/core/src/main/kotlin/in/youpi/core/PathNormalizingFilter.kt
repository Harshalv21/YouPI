package `in`.youpi.core

import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.stereotype.Component
import org.springframework.web.server.ServerWebExchange
import org.springframework.web.server.WebFilter
import org.springframework.web.server.WebFilterChain
import reactor.core.publisher.Mono

/**
 * Collapses multiple consecutive slashes in the request path (e.g.
 * "/api//v1/auth/firebase/verify" -> "/api/v1/auth/firebase/verify")
 * BEFORE routing happens. Without this, a double-slash path fails to
 * match any RouterFunction pattern and falls through to Spring's
 * static resource handler, producing a misleading 404.
 * Runs at the very front of the filter chain.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class PathNormalizingFilter : WebFilter {

    override fun filter(exchange: ServerWebExchange, chain: WebFilterChain): Mono<Void> {
        val path = exchange.request.uri.path
        val normalized = path.replace(Regex("/+"), "/")
        return if (normalized != path) {
            val newRequest = exchange.request.mutate().path(normalized).build()
            chain.filter(exchange.mutate().request(newRequest).build())
        } else {
            chain.filter(exchange)
        }
    }
}