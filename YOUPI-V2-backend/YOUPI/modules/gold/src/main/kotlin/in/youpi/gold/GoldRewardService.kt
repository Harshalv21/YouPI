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

        // 1 YouPI Gold Coin = ₹0.10. Coins credited per recharge = reward
        // value in rupees (1% of recharge) divided by this, rounded to the
        // nearest whole coin -- e.g. a ₹350 recharge earns ₹3.50 (1%),
        // which is 3.50 / 0.10 = 35 coins. The coin count is just a display
        // denomination of the SAME rupee value already being credited to
        // balance_rupees below, not a second/different reward -- a user's
        // actual worth is still exactly 1% of what they recharged, only
        // now expressed as a coin count instead of always "+1 coin" per
        // recharge regardless of amount.
        val COIN_VALUE_RUPEES: BigDecimal = BigDecimal("0.10")
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

        // Coins are a denomination of rewardValueRupees (see COIN_VALUE_RUPEES
        // doc comment above), not a separate amount -- balance_rupees below
        // still gets the exact 1% rupee value either way.
        val coinsToCredit = rewardValueRupees
            .divide(COIN_VALUE_RUPEES, 0, RoundingMode.HALF_UP)
            .toInt()
            .coerceAtLeast(0)

        val insertedId = goldRewardLedgerRepository.insertIfNotExists(
            userId, rechargeTxnId, rechargeAmount, rewardValueRupees
        )

        if (insertedId == null) return // webhook retry, already credited — skip

        goldWalletRepository.creditCoin(userId, coinsToCredit, rewardValueRupees)
    }
}