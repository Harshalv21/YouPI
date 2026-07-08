package `in`.youpi.security

import at.favre.lib.crypto.bcrypt.BCrypt
import org.slf4j.LoggerFactory
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.stereotype.Service
import java.security.SecureRandom
import java.time.Duration
import kotlinx.coroutines.reactor.awaitSingle
import kotlinx.coroutines.reactor.awaitSingleOrNull

/**
 * OTP generation, hashing, and verification service.
 * Used by auth (LOGIN) and KYC (AADHAAR) modules.
 *
 * - 6-digit secure random OTP
 * - BCrypt hashed (cost=12)
 * - Redis storage with 300s TTL
 * - Max 3 attempts; lockout for 10min on 3rd failure
 * - NEVER logs the OTP value
 */
@Service
class OtpService(
    private val redisTemplate: ReactiveStringRedisTemplate
) {

    private val log = LoggerFactory.getLogger(javaClass)
    private val secureRandom = SecureRandom()

    companion object {
        const val OTP_TTL_SECONDS = 300L     // 5 minutes
        const val MAX_ATTEMPTS = 3
        const val LOCKOUT_SECONDS = 600L     // 10 minutes
        const val BCRYPT_COST = 12
    }

    /**
     * Generate a 6-digit OTP. Returns raw OTP string (to send via SMS).
     */
    fun generateOtp(): String {
        val otp = (100000 + secureRandom.nextInt(900000)).toString()
        // NEVER log the actual OTP value
        log.debug("OTP generated (not logging value)")
        return otp
    }

    /**
     * Hash OTP with BCrypt (cost=12) for storage.
     */
    fun hashOtp(otp: String): String {
        return BCrypt.withDefaults().hashToString(BCRYPT_COST, otp.toCharArray())
    }

    /**
     * Verify OTP input against BCrypt hash. Constant-time comparison.
     */
    fun verifyOtp(input: String, hash: String): Boolean {
        val result = BCrypt.verifyer().verify(input.toCharArray(), hash)
        return result.verified
    }

    /**
     * Store OTP hash in Redis with TTL.
     * Key format: "otp:{purpose}:{mobile}"
     */
    suspend fun storeOtp(purpose: String, mobile: String, otpHash: String) {
        val key = "otp:$purpose:$mobile"
        redisTemplate.opsForValue()
            .set(key, otpHash, Duration.ofSeconds(OTP_TTL_SECONDS))
            .subscribe()

        // Initialize attempt counter
        val attemptKey = "otp_attempts:$purpose:$mobile"
        redisTemplate.opsForValue()
            .set(attemptKey, "0", Duration.ofSeconds(OTP_TTL_SECONDS))
            .subscribe()
    }

    /**
     * Retrieve stored OTP hash from Redis.
     */
    suspend fun getStoredHash(purpose: String, mobile: String): String? {
        val key = "otp:$purpose:$mobile"
        return try {
            redisTemplate.opsForValue().get(key).awaitSingleOrNull()
        } catch (e: Exception) {
            log.error("Redis error in getStoredHash: {}", e.message)
            null
        }
    }

    /**
     * Increment attempt counter. Returns current attempt count.
     * On reaching MAX_ATTEMPTS: sets lockout key.
     */
    suspend fun incrementAttempts(purpose: String, mobile: String): Int {
        val attemptKey = "otp_attempts:$purpose:$mobile"
        return try {
            val attempts = (redisTemplate.opsForValue().increment(attemptKey).awaitSingle() ?: 1L).toInt()

            if (attempts >= MAX_ATTEMPTS) {
                val lockKey = "otp_lock:$purpose:$mobile"
                redisTemplate.opsForValue()
                    .set(lockKey, "locked", Duration.ofSeconds(LOCKOUT_SECONDS))
                    .subscribe()
                log.warn("OTP max attempts reached for purpose={}, locking for {}s", purpose, LOCKOUT_SECONDS)
            }
            attempts
        } catch (e: Exception) {
            log.error("Redis error in incrementAttempts: {}", e.message)
            1
        }
    }

    /**
     * Check if the mobile is locked out for the given purpose.
     */
    suspend fun isLockedOut(purpose: String, mobile: String): Boolean {
        val lockKey = "otp_lock:$purpose:$mobile"
        return try {
            redisTemplate.hasKey(lockKey).awaitSingle() ?: false
        } catch (e: Exception) {
            log.error("Redis error in isLockedOut: {}", e.message)
            false
        }
    }

    /**
     * Clear OTP data after successful verification.
     */
    suspend fun clearOtp(purpose: String, mobile: String) {
        val key = "otp:$purpose:$mobile"
        val attemptKey = "otp_attempts:$purpose:$mobile"
        redisTemplate.delete(key).subscribe()
        redisTemplate.delete(attemptKey).subscribe()
    }
}
