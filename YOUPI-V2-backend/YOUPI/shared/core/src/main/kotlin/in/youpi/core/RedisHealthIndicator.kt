package `in`.youpi.core

import org.springframework.boot.actuate.health.Health
import org.springframework.boot.actuate.health.ReactiveHealthIndicator
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.stereotype.Component
import reactor.core.publisher.Mono

/**
 * Custom Redis health indicator for Cloud Run readiness probes.
 */
@Component
class RedisHealthIndicator(
    private val redisTemplate: ReactiveStringRedisTemplate
) : ReactiveHealthIndicator {

    override fun health(): Mono<Health> {
        return redisTemplate.connectionFactory
            .reactiveConnection
            .ping()
            .map { Health.up().withDetail("redis", "connected").build() }
            .onErrorResume {
                Mono.just(Health.down().withDetail("redis", it.message ?: "unavailable").build())
            }
    }
}
