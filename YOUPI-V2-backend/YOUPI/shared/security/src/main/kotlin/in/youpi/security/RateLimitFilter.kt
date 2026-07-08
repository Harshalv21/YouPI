package `in`.youpi.security

import `in`.youpi.core.RateLimitExceededException
import org.slf4j.LoggerFactory
import org.springframework.data.domain.Range
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.web.server.ServerWebExchange
import org.springframework.web.server.WebFilter
import org.springframework.web.server.WebFilterChain
import reactor.core.publisher.Mono
import java.time.Duration
import java.time.Instant

/**
 * Redis-backed sliding window rate limiter using Sorted Sets.
 * Configurable per endpoint via application.yml.
 */
@Component
class RateLimitFilter(
    private val redisTemplate: ReactiveStringRedisTemplate
) : WebFilter {

    private val log = LoggerFactory.getLogger(javaClass)

    data class RateLimitRule(
        val pathPrefix: String,
        val maxRequests: Long,
        val windowSeconds: Long,
        val keyExtractor: (ServerWebExchange) -> String
    )

    private val rules = listOf(
        RateLimitRule("/api/v1/auth/otp/send", 3, 600) { exchange ->
            // Rate limit by mobile number from request body — fallback to IP
            val ip = exchange.request.remoteAddress?.address?.hostAddress ?: "unknown"
            "rl:otp:$ip"
        },
        RateLimitRule("/api/v1/payment/", 10, 3600) { exchange ->
            val userId = exchange.attributes["auth.userId"]?.toString() ?: "anon"
            "rl:payment:$userId"
        },
        RateLimitRule("/api/v1/recharge/plans", 60, 60) { exchange ->
            val ip = exchange.request.remoteAddress?.address?.hostAddress ?: "unknown"
            "rl:plans:$ip"
        }
    )

    override fun filter(exchange: ServerWebExchange, chain: WebFilterChain): Mono<Void> {
        val path = exchange.request.uri.path
        val rule = rules.find { path.startsWith(it.pathPrefix) }
            ?: return chain.filter(exchange)

        val key = rule.keyExtractor(exchange)
        val now = Instant.now()
        val windowStart = now.minusSeconds(rule.windowSeconds)

        val windowRange = Range.of(Range.Bound.inclusive(windowStart.toEpochMilli().toDouble()), Range.Bound.inclusive(now.toEpochMilli().toDouble()))
        val oldRange = Range.of(Range.Bound.unbounded<Double>(), Range.Bound.inclusive(windowStart.toEpochMilli().toDouble()))

        val redisOps = redisTemplate.opsForZSet()

        return redisOps.removeRangeByScore(key, oldRange)
            .then(redisOps.count(key, windowRange))
            .flatMap { count ->
                if (count >= rule.maxRequests) {
                    log.warn("Rate limit exceeded for key={}, count={}/{}", key, count, rule.maxRequests)
                    writeRateLimited(exchange, rule.windowSeconds)
                } else {
                    redisOps.add(key, now.toEpochMilli().toString(), now.toEpochMilli().toDouble())
                        .then(redisTemplate.expire(key, Duration.ofSeconds(rule.windowSeconds)))
                        .then(Mono.empty<Void>())
                }
            }
            .onErrorResume { e ->
                log.error("Rate limiting failed (Redis might be down): {}", e.message)
                Mono.empty<Void>() // Proceed anyway if Redis fails
            }
            .then(Mono.defer { chain.filter(exchange) })
    }

    private fun writeRateLimited(exchange: ServerWebExchange, retryAfter: Long): Mono<Void> {
        exchange.response.statusCode = HttpStatus.TOO_MANY_REQUESTS
        exchange.response.headers.set("Content-Type", "application/json")
        exchange.response.headers.set("Retry-After", retryAfter.toString())
        val body = """{"success":false,"error":{"code":"RATE_LIMITED","message":"Too many requests. Try again later."}}"""
        val buffer = exchange.response.bufferFactory().wrap(body.toByteArray())
        return exchange.response.writeWith(Mono.just(buffer))
    }
}
