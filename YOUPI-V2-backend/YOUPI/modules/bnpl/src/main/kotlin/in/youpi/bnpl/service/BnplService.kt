package `in`.youpi.bnpl.service

import `in`.youpi.core.BaseException
import `in`.youpi.core.Result
import `in`.youpi.events.PubSubPublisher
import kotlinx.coroutines.reactor.awaitSingle
import kotlinx.coroutines.reactor.awaitSingleOrNull
import org.slf4j.LoggerFactory
import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.util.UUID

// ── Entities ──

@Table("bnpl_applications")
data class BnplApplicationEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val employmentType: String? = null,
    val monthlyIncome: BigDecimal? = null,
    val cibilScore: Short? = null,
    val cibilReportId: String? = null,
    val cibilConsent: Boolean = false,
    val tcConsent: Boolean = false,
    val approvedLimit: BigDecimal? = null,
    val status: String = "SUBMITTED",
    val rejectionReason: String? = null,
    val reviewedBy: UUID? = null,
    val reviewedAt: Instant? = null,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface BnplApplicationRepository : CoroutineCrudRepository<BnplApplicationEntity, UUID> {
    @Query("SELECT * FROM bnpl_applications WHERE user_id = :userId ORDER BY created_at DESC LIMIT 1")
    suspend fun findLatestByUserId(userId: UUID): BnplApplicationEntity?
    suspend fun findAllByStatus(status: String): List<BnplApplicationEntity>
}

@Table("bnpl_accounts")
data class BnplAccountEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val applicationId: UUID,
    val totalLimit: BigDecimal,
    val usedLimit: BigDecimal = BigDecimal.ZERO,
    val status: String = "ACTIVE",
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface BnplAccountRepository : CoroutineCrudRepository<BnplAccountEntity, UUID> {
    suspend fun findByUserId(userId: UUID): BnplAccountEntity?
}

// ── DTOs ──

data class BnplStep1Request(val employmentType: String, val monthlyIncome: BigDecimal)
data class BnplStep2Request(val cibilConsent: Boolean)
data class BnplStep3Request(val tcConsent: Boolean)

data class BnplStatusResponse(
    val userId: UUID,
    val applicationStatus: String?,
    val totalLimit: BigDecimal?,
    val usedLimit: BigDecimal?,
    val availableLimit: BigDecimal?,
    val accountStatus: String?
)

// ── Exceptions ──

sealed class BnplException(code: String, message: String, httpStatus: Int = 400)
    : BaseException(code, message) { override val httpStatus: Int = httpStatus }

class BnplApplicationExistsException : BnplException(
    "BNPL_APPLICATION_EXISTS", "Active application already exists.", 409
)
class BnplNotEligibleException(reason: String) : BnplException(
    "BNPL_NOT_ELIGIBLE", "Not eligible: $reason", 403
)
class BnplSessionExpiredException : BnplException(
    "BNPL_SESSION_EXPIRED", "Session expired. Please restart from step 1.", 400  // ← naya
)

@Service
class BnplService(
    private val appRepo: BnplApplicationRepository,
    private val accountRepo: BnplAccountRepository,
    private val redisTemplate: ReactiveStringRedisTemplate,
    private val pubSubPublisher: PubSubPublisher              // ← TODO replace kiya
) {
    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        private val SESSION_TTL = Duration.ofMinutes(30)
        private const val SESSION_PREFIX = "bnpl_session:"
        private const val CIBIL_THRESHOLD = 650
    }

    suspend fun getStatus(userId: UUID): BnplStatusResponse {
        val account = accountRepo.findByUserId(userId)
        val app = appRepo.findLatestByUserId(userId)

        return BnplStatusResponse(
            userId = userId,
            applicationStatus = app?.status,
            totalLimit = account?.totalLimit,
            usedLimit = account?.usedLimit,
            availableLimit = account?.let { it.totalLimit.subtract(it.usedLimit) },
            accountStatus = account?.status
        )
    }

    suspend fun submitStep1(userId: UUID, req: BnplStep1Request): Result<String, BnplException> {
        val existing = appRepo.findLatestByUserId(userId)
        if (existing != null && existing.status in listOf("SUBMITTED", "UNDER_REVIEW")) {
            return Result.failure(BnplApplicationExistsException())
        }

        val sessionKey = "$SESSION_PREFIX$userId"

        // ← .subscribe() hata, awaitSingle() use karo — proper coroutine await
        redisTemplate.opsForHash<String, String>().putAll(
            sessionKey,
            mapOf(
                "employmentType" to req.employmentType,
                "monthlyIncome"  to req.monthlyIncome.toPlainString(),
                "step"           to "1"
            )
        ).awaitSingle()
        redisTemplate.expire(sessionKey, SESSION_TTL).awaitSingle()

        return Result.success("Step 1 saved. Proceed to step 2 (CIBIL consent).")
    }

    suspend fun submitStep2(userId: UUID, req: BnplStep2Request): Result<String, BnplException> {
        if (!req.cibilConsent) return Result.failure(BnplNotEligibleException("CIBIL consent required"))

        val sessionKey = "$SESSION_PREFIX$userId"

        // ← step 1 session missing check
        val step = redisTemplate.opsForHash<String, String>()
            .get(sessionKey, "step").awaitSingleOrNull()
        if (step == null) return Result.failure(BnplSessionExpiredException())

        // ← .subscribe() hata, awaitSingle() use karo
        redisTemplate.opsForHash<String, String>()
            .put(sessionKey, "cibilConsent", "true").awaitSingle()
        redisTemplate.opsForHash<String, String>()
            .put(sessionKey, "step", "2").awaitSingle()
        redisTemplate.expire(sessionKey, SESSION_TTL).awaitSingle()  // TTL refresh

        // TODO: Trigger CIBIL check via Karza API
        return Result.success("Step 2 saved. Proceed to step 3 (T&C consent).")
    }

    suspend fun submitStep3(userId: UUID, req: BnplStep3Request): Result<BnplStatusResponse, BnplException> {
        if (!req.tcConsent) return Result.failure(BnplNotEligibleException("T&C consent required"))

        val sessionKey = "$SESSION_PREFIX$userId"

        // ← .collectList().block() hata — awaitSingleOrNull() use karo
        val sessionData = redisTemplate.opsForHash<String, String>()
        .entries(sessionKey)
        .collectList()
        .awaitSingle()

        val session = sessionData.associate { it.key to it.value }
        // ← session missing check
        if (session["step"] == null) return Result.failure(BnplSessionExpiredException())

        val app = appRepo.save(
            BnplApplicationEntity(
                userId = userId,
                employmentType = session["employmentType"],
                monthlyIncome  = session["monthlyIncome"]?.let { BigDecimal(it) },
                cibilConsent   = true,
                tcConsent      = true,
                status         = "SUBMITTED"
            )
        )

        // ← .subscribe() hata
        redisTemplate.delete(sessionKey).awaitSingleOrNull()

        log.info("BNPL application submitted: userId={}, appId={}", userId, app.id)

        // ← TODO replace kiya — Pub/Sub event publish
        try {
            pubSubPublisher.publish(
                "bnpl-application-submitted",
                mapOf(
                    "applicationId" to app.id.toString(),
                    "userId"        to userId.toString()
                )
            )
        } catch (e: Exception) {
            log.error("Failed to publish bnpl-application-submitted event: {}", e.message)
        }

        return Result.success(getStatus(userId))
    }

    suspend fun autoDecide(applicationId: UUID) {
        val app = appRepo.findById(applicationId) ?: return

        // TODO: Fetch real CIBIL score via Karza API
        val cibilScore: Short = 720

        if (cibilScore >= CIBIL_THRESHOLD) {
            val limit = calculateLimit(app.monthlyIncome, cibilScore)

            val updatedApp = appRepo.save(
                app.copy(
                    cibilScore    = cibilScore,
                    approvedLimit = limit,
                    status        = "APPROVED",
                    updatedAt     = Instant.now()
                )
            )

            accountRepo.save(
                BnplAccountEntity(
                    userId        = app.userId,
                    applicationId = updatedApp.id!!,
                    totalLimit    = limit
                )
            )

            log.info("BNPL auto-approved: userId={}, limit=₹{}, CIBIL={}", app.userId, limit, cibilScore)
        } else {
            appRepo.save(
                app.copy(
                    cibilScore      = cibilScore,
                    status          = "REJECTED",
                    rejectionReason = "CIBIL score $cibilScore below threshold $CIBIL_THRESHOLD",
                    updatedAt       = Instant.now()
                )
            )
            log.info("BNPL auto-rejected: userId={}, CIBIL={}", app.userId, cibilScore)
        }

        // TODO:
    }

    private fun calculateLimit(monthlyIncome: BigDecimal?, cibilScore: Short): BigDecimal {
        val baseMultiplier = when {
            cibilScore >= 750 -> BigDecimal("3.0")
            cibilScore >= 700 -> BigDecimal("2.0")
            else -> BigDecimal("1.5")
        }

        val income = monthlyIncome ?: BigDecimal("15000")
        val limit = income.multiply(baseMultiplier)
            .setScale(0, java.math.RoundingMode.DOWN)

        return limit.min(BigDecimal("100000"))
    }
}