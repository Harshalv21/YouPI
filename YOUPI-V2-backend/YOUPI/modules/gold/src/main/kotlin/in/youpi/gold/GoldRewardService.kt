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
        // THIS VERSION: lowered to ₹20 for coin-count-only testing (no real
        // gold/Augmont investment yet -- deferred to the next version once
        // bank API integration lands). MUST STAY IN SYNC with:
        //   - RechargeService.kt's GOLD_ELIGIBLE_PLAN_AMOUNT
        //   - emi_selection_screen.dart's `if (plan.price >= 20)` check
        // If any of these three drift apart, the animation, the "eligible"
        // log line, and the actual DB credit will disagree with each other.
        val MIN_RECHARGE_FOR_REWARD: BigDecimal = BigDecimal("20")
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