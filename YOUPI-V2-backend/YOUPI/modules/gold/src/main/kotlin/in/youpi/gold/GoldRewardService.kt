package `in`.youpi.gold

import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.UUID

@Service
class GoldRewardService(
    private val goldWalletRepository: GoldWalletRepository,
    private val goldRewardLedgerRepository: GoldRewardLedgerRepository
) {

    companion object {
        val MIN_RECHARGE_FOR_REWARD: BigDecimal = BigDecimal("249")
        val REWARD_PERCENTAGE: BigDecimal = BigDecimal("0.01")
    }

    /**
     * Called ONLY from RechargeService.handleWebhookCaptured() — userId comes
     * from the recharge order record (server-side, not client-supplied).
     */
    @Transactional
    suspend fun creditRewardForRecharge(
        userId: UUID,
        rechargeTxnId: String,
        rechargeAmount: BigDecimal
    ) {
        if (rechargeAmount < MIN_RECHARGE_FOR_REWARD) return

        val rewardValueRupees = rechargeAmount
            .multiply(REWARD_PERCENTAGE)
            .setScale(2, RoundingMode.HALF_UP)

        val insertedId = goldRewardLedgerRepository.insertIfNotExists(
            userId, rechargeTxnId, rechargeAmount, rewardValueRupees
        )

        if (insertedId == null) return // webhook retry, already credited — skip

        goldWalletRepository.creditCoin(userId, rewardValueRupees)
    }
}