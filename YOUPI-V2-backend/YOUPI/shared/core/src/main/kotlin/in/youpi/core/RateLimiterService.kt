package `in`.youpi.core.ratelimit

import kotlinx.coroutines.reactor.awaitSingleOrNull
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.stereotype.Service
import java.time.Duration

/**
 * Distributed rate limiter using Redis fixed-window counters.
 * Works correctly across multiple Cloud Run instances (unlike in-memory limiters).
 */
@Service
class RateLimiterService(
    private val redisTemplate: ReactiveStringRedisTemplate
) {
    /**
     * @param key unique identifier for this rate-limited action, e.g. "rl:wallet:topup:{userId}"
     * @param limit max requests allowed within the window
     * @param windowSeconds window duration in seconds
     * @return true if the request is allowed, false if the limit has been exceeded
     */
    suspend fun isAllowed(key: String, limit: Long, windowSeconds: Long): Boolean {
        val count = redisTemplate.opsForValue().increment(key).awaitSingleOrNull() ?: 0L

        if (count == 1L) {
            // first request in this window — set expiry so the counter resets
            redisTemplate.expire(key, Duration.ofSeconds(windowSeconds)).awaitSingleOrNull()
        }

        return count <= limit
    }
}