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
        // Reverted to ₹249 for real launch (was temporarily lowered to ₹20
        // during testing for coin-count-only verification). MUST STAY IN
        // SYNC with:
        //   - RechargeService.kt's GOLD_ELIGIBLE_PLAN_AMOUNT
        //   - emi_selection_screen.dart's `if (plan.price >= 249)` check
        // If any of these three drift apart, the animation, the "eligible"
        // log line, and the actual DB credit will disagree with each other.
        //
        // NOTE: this is the MOBILE recharge minimum only. DTH recharge has
        // NO minimum-eligibility rule (business decision) -- see
        // minimumEligibleAmount param below, which DTH callers override to
        // BigDecimal.ZERO. Do not change this constant's value to "fix"
        // DTH eligibility -- that would incorrectly also change mobile's
        // long-standing ₹249 threshold.
        val MIN_RECHARGE_FOR_REWARD: BigDecimal = BigDecimal("249")
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

        // ← NEW: pure calculation, no DB reads/writes/ledger inserts --
        // mirrors creditRewardForRecharge()'s exact eligibility gate and
        // rounding so a caller can know/display what WAS (or will be)
        // credited without re-deriving the math or touching the ledger.
        // Same minimumEligibleAmount contract as creditRewardForRecharge():
        // MOBILE callers omit it (defaults to ₹249), DTH callers pass
        // ZERO. Returns null when not eligible -- callers treat null as
        // "no reward, so no reward-linked push either".
        data class RewardPreview(val earnedCoins: Int, val earnedValueRupees: BigDecimal)

        fun previewReward(
            rechargeAmount: BigDecimal,
            minimumEligibleAmount: BigDecimal = MIN_RECHARGE_FOR_REWARD
        ): RewardPreview? {
            if (rechargeAmount < minimumEligibleAmount) return null

            val earnedValueRupees = rechargeAmount
                .multiply(REWARD_PERCENTAGE)
                .setScale(2, RoundingMode.HALF_UP)

            val earnedCoins = earnedValueRupees
                .divide(COIN_VALUE_RUPEES, 0, RoundingMode.HALF_UP)
                .toInt()
                .coerceAtLeast(0)

            return RewardPreview(earnedCoins, earnedValueRupees)
        }
    }

    /**
     * Called from RechargeService (mobile recharge -- handleWebhookCaptured()
     * via deliverAndResolve(), and resolveA1TopupOutcome() for reconciled
     * orders) AND from DthRechargeService (DTH recharge).
     *
     * ← NEW: minimumEligibleAmount param, default = MIN_RECHARGE_FOR_REWARD
     * (₹249). Every existing call site (mobile) doesn't pass this param,
     * so its behavior is EXACTLY unchanged from before this change. DTH
     * callers explicitly pass BigDecimal.ZERO -- DTH has no
     * minimum-eligibility business rule, every successful DTH recharge
     * earns 1% regardless of amount.
     *
     * The ledger/idempotency mechanism below (insertIfNotExists, keyed on
     * rechargeTxnId) is completely untouched -- only the eligibility gate
     * above it is now caller-configurable. This keeps the single reward
     * ledger and single dedup mechanism centralized here rather than
     * duplicated per recharge type, per the requirement to not create a
     * separate DTH reward path.
     */
    @Transactional
    suspend fun creditRewardForRecharge(
        userId: UUID,
        rechargeTxnId: String,
        rechargeAmount: BigDecimal,
        minimumEligibleAmount: BigDecimal = MIN_RECHARGE_FOR_REWARD
    ) {
        if (rechargeAmount < minimumEligibleAmount) return

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