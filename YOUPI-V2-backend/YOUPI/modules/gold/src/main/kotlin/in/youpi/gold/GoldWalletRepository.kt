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
    val coinCount: Int = 0,
    val balanceRupees: BigDecimal = BigDecimal.ZERO,
    val updatedAt: Instant = Instant.now()
)

@Table("gold_reward_ledger")
data class GoldRewardLedgerEntity(
    @Id val id: Long? = null,
    val userId: UUID,
    val rechargeTxnId: String,
    val rechargeAmount: BigDecimal,
    val rewardValueRupees: BigDecimal,
    val status: String = "CREDITED",
    val createdAt: Instant = Instant.now()
)

@Table("gold_withdraw_requests")
data class GoldWithdrawRequestEntity(
    @Id val id: Long? = null,
    val userId: UUID,
    val amountRupees: BigDecimal,
    val status: String = "PENDING",
    val createdAt: Instant = Instant.now()
)

// ── Repositories ──

interface GoldWalletRepository : CoroutineCrudRepository<GoldWalletEntity, UUID> {

    suspend fun findByUserId(userId: UUID): GoldWalletEntity?

    @Query(
        """
        INSERT INTO gold_wallet (user_id, coin_count, balance_rupees, updated_at)
        VALUES (:userId, 1, :rewardValueRupees, now())
        ON CONFLICT (user_id) DO UPDATE
        SET coin_count = gold_wallet.coin_count + 1,
            balance_rupees = gold_wallet.balance_rupees + :rewardValueRupees,
            updated_at = now()
        """
    )
    suspend fun creditCoin(userId: UUID, rewardValueRupees: BigDecimal)

    @Query(
        """
        UPDATE gold_wallet
        SET balance_rupees = balance_rupees - :amount, updated_at = now()
        WHERE user_id = :userId AND balance_rupees >= :amount
        RETURNING user_id
        """
    )
    suspend fun deductBalance(userId: UUID, amount: BigDecimal): UUID?
}

interface GoldRewardLedgerRepository : CoroutineCrudRepository<GoldRewardLedgerEntity, Long> {

    suspend fun findByRechargeTxnId(rechargeTxnId: String): GoldRewardLedgerEntity?

    @Query(
        """
        INSERT INTO gold_reward_ledger
            (user_id, recharge_txn_id, recharge_amount, reward_value_rupees, status)
        VALUES (:userId, :rechargeTxnId, :rechargeAmount, :rewardValueRupees, 'CREDITED')
        ON CONFLICT (recharge_txn_id) DO NOTHING
        RETURNING id
        """
    )
    suspend fun insertIfNotExists(
        userId: UUID,
        rechargeTxnId: String,
        rechargeAmount: BigDecimal,
        rewardValueRupees: BigDecimal
    ): Long?
}

interface GoldWithdrawRequestRepository : CoroutineCrudRepository<GoldWithdrawRequestEntity, Long>