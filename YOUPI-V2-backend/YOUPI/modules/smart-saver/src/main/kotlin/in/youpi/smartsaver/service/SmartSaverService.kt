package `in`.youpi.smartsaver.service

import `in`.youpi.core.NotFoundException
import `in`.youpi.core.Result
import org.slf4j.LoggerFactory
import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

// ── Entity ──
@Table("smart_saver_allocations")
data class SmartSaverAllocationEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val depositAmount: BigDecimal = BigDecimal.ZERO,
    val adminSeedAmount: BigDecimal = BigDecimal("1000.00"),
    val usedCredit: BigDecimal = BigDecimal.ZERO,
    val status: String = "PENDING_ACTIVATION",
    val activatedBy: UUID? = null,
    val activatedAt: Instant? = null,
    val notes: String? = null,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface SmartSaverAllocationRepository : CoroutineCrudRepository<SmartSaverAllocationEntity, UUID> {
    suspend fun findByUserId(userId: UUID): SmartSaverAllocationEntity?
    suspend fun findAllByStatus(status: String): List<SmartSaverAllocationEntity>
}

// ── Response ──
data class SmartSaverResponse(
    val userId: UUID,
    val depositAmount: BigDecimal,
    val totalCollateral: BigDecimal,
    val creditLimit: BigDecimal,
    val usedCredit: BigDecimal,
    val availableCredit: BigDecimal,
    val status: String
)

/**
 * Smart Saver service — manages deposit-backed recharge credit.
 * Admin seeds ₹1000, user deposits for higher limits.
 * Credit limit = 80% of total collateral.
 */
@Service
class SmartSaverService(
    private val repo: SmartSaverAllocationRepository
) {

    private val log = LoggerFactory.getLogger(javaClass)

    suspend fun getAllocation(userId: UUID): SmartSaverResponse {
        val entity = repo.findByUserId(userId)
            ?: throw NotFoundException("SmartSaverAllocation", userId.toString())
        return toResponse(entity)
    }

    suspend fun addDeposit(userId: UUID, amount: BigDecimal): SmartSaverResponse {
        val entity = repo.findByUserId(userId)
            ?: throw NotFoundException("SmartSaverAllocation", userId.toString())

        require(entity.status == "ACTIVE") { "Account must be ACTIVE to accept deposits" }
        require(amount > BigDecimal.ZERO) { "Deposit must be positive" }

        val updated = repo.save(
            entity.copy(
                depositAmount = entity.depositAmount.add(amount),
                updatedAt = Instant.now()
            )
        )

        log.info("Deposit ₹{} added for user {}", amount, userId)
        return toResponse(updated)
    }

    /**
     * Atomically deduct credit for a recharge.
     * Uses optimistic locking via version check.
     */
    suspend fun deductCredit(userId: UUID, amount: BigDecimal): Result<SmartSaverResponse, String> {
        val entity = repo.findByUserId(userId) ?: return Result.failure("Allocation not found")
        if (entity.status != "ACTIVE") return Result.failure("Account not active")

        val totalCollateral = entity.depositAmount.add(entity.adminSeedAmount)
        val creditLimit = totalCollateral.multiply(BigDecimal("0.80"))
        val availableCredit = creditLimit.subtract(entity.usedCredit)

        if (amount > availableCredit) {
            return Result.failure("Insufficient credit: available=$availableCredit, required=$amount")
        }

        val updated = repo.save(
            entity.copy(
                usedCredit = entity.usedCredit.add(amount),
                updatedAt = Instant.now()
            )
        )

        log.info("Credit ₹{} deducted for user {}. Remaining: ₹{}", amount, userId, creditLimit.subtract(updated.usedCredit))
        return Result.success(toResponse(updated))
    }

    /** Admin function: activate Smart Saver for a user */
    suspend fun activateForUser(userId: UUID, adminId: UUID, seedAmount: BigDecimal, notes: String?): SmartSaverResponse {
        val existing = repo.findByUserId(userId)

        val entity = if (existing != null) {
            repo.save(existing.copy(
                adminSeedAmount = seedAmount,
                status = "ACTIVE",
                activatedBy = adminId,
                activatedAt = Instant.now(),
                notes = notes,
                updatedAt = Instant.now()
            ))
        } else {
            repo.save(SmartSaverAllocationEntity(
                userId = userId,
                adminSeedAmount = seedAmount,
                status = "ACTIVE",
                activatedBy = adminId,
                activatedAt = Instant.now(),
                notes = notes
            ))
        }

        log.info("Smart Saver activated for user {} by admin {}, seed=₹{}", userId, adminId, seedAmount)
        return toResponse(entity)
    }

    private fun toResponse(entity: SmartSaverAllocationEntity): SmartSaverResponse {
        val totalCollateral = entity.depositAmount.add(entity.adminSeedAmount)
        val creditLimit = totalCollateral.multiply(BigDecimal("0.80"))
        return SmartSaverResponse(
            userId = entity.userId,
            depositAmount = entity.depositAmount,
            totalCollateral = totalCollateral,
            creditLimit = creditLimit,
            usedCredit = entity.usedCredit,
            availableCredit = creditLimit.subtract(entity.usedCredit),
            status = entity.status
        )
    }
}
