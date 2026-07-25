package `in`.youpi.gold

import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

// ── Entities ──

@Table("gold_wallet")
data class GoldWalletEntity(
    @Id val userId: UUID,
    val totalGrams: BigDecimal = BigDecimal.ZERO,
    val updatedAt: Instant = Instant.now()
)

@Table("gold_reward_ledger")
data class GoldRewardLedgerEntity(
    @Id val id: Long? = null,
    val userId: UUID,
    val rechargeTxnId: String,
    val rechargeAmount: BigDecimal,
    val rewardValueRupees: BigDecimal,
    val goldRateAtCredit: BigDecimal,
    val goldGrams: BigDecimal,
    val status: String = "CREDITED",
    val createdAt: Instant = Instant.now()
)

@Table("gold_withdraw_requests")
data class GoldWithdrawRequestEntity(
    @Id val id: Long? = null,
    val userId: UUID,
    val amountRupees: BigDecimal,
    val goldGramsDeducted: BigDecimal,
    val goldRateAtWithdraw: BigDecimal,
    val status: String = "PENDING",
    val createdAt: Instant = Instant.now()
)

// ── Repositories ──

interface GoldWalletRepository : CoroutineCrudRepository<GoldWalletEntity, UUID> {
    suspend fun findByUserId(userId: UUID): GoldWalletEntity?

    @Query("UPDATE gold_wallet SET total_grams = total_grams + :grams, updated_at = NOW() WHERE user_id = :userId AND total_grams + :grams >= 0 RETURNING user_id")
    suspend fun atomicGramsUpdate(userId: UUID, grams: BigDecimal): Int

    @Query("INSERT INTO gold_wallet (user_id, total_grams) VALUES (:userId, 0) ON CONFLICT (user_id) DO NOTHING")
    suspend fun ensureWalletExists(userId: UUID)
}

interface GoldRewardLedgerRepository : CoroutineCrudRepository<GoldRewardLedgerEntity, Long> {
    suspend fun findByRechargeTxnId(rechargeTxnId: String): GoldRewardLedgerEntity?
}

interface GoldWithdrawRequestRepository : CoroutineCrudRepository<GoldWithdrawRequestEntity, Long>