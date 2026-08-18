package `in`.youpi.core

import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.stereotype.Component
import org.springframework.web.server.ServerWebExchange
import org.springframework.web.server.WebFilter
import org.springframework.web.server.WebFilterChain
import reactor.core.publisher.Mono

/**
 * Applies standard security headers (X-Frame-Options, CSP, HSTS, etc.) to
 * every response. See SecurityHeaders.kt for the actual header values and
 * why -- this filter is just the delivery mechanism for the normal-response
 * path; GlobalExceptionHandler re-applies the same set for error responses.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 2)
class SecurityHeadersFilter : WebFilter {

    override fun filter(exchange: ServerWebExchange, chain: WebFilterChain): Mono<Void> {
        applySecurityHeaders(exchange.response.headers)
        return chain.filter(exchange)
    }
}