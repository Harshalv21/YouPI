package `in`.youpi.gold

import `in`.youpi.core.BaseException
import `in`.youpi.core.Result
import `in`.youpi.invest.service.InvestService
import `in`.youpi.wallet.service.WalletService
import org.slf4j.LoggerFactory
import org.springframework.r2dbc.connection.R2dbcTransactionManager
import org.springframework.stereotype.Service
import org.springframework.transaction.reactive.TransactionalOperator
import org.springframework.transaction.reactive.executeAndAwait
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.UUID

// ── DTOs ──

data class GoldWithdrawRequest(
    val amountRupees: BigDecimal
)

data class GoldWithdrawResponse(
    val userId: UUID,
    val amountRupees: BigDecimal,
    val goldGramsDeducted: BigDecimal,
    val remainingGoldGrams: BigDecimal
)

// ── Exceptions ──

sealed class GoldWithdrawException(code: String, message: String, httpStatus: Int = 400)
    : BaseException(code, message) { override val httpStatus: Int = httpStatus }

class MinimumWithdrawException : GoldWithdrawException(
    "MIN_WITHDRAW", "Minimum withdrawal amount is ₹50", 400
)

class InsufficientGoldBalanceException(val availableRupeesValue: BigDecimal, val requiredRupees: BigDecimal) : GoldWithdrawException(
    "INSUFFICIENT_GOLD_BALANCE", "Insufficient gold balance: available worth ₹$availableRupeesValue, required ₹$requiredRupees", 402
)

class GoldRateFetchFailedException : GoldWithdrawException(
    "GOLD_RATE_UNAVAILABLE", "Unable to fetch current gold rate for withdrawal", 502
)

@Service
class GoldWithdrawService(
    private val goldWalletRepo: GoldWalletRepository,
    private val goldWithdrawRepo: GoldWithdrawRequestRepository,
    private val investService: InvestService,
    private val walletService: WalletService,
    private val txManager: R2dbcTransactionManager
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val txOperator = TransactionalOperator.create(txManager)

    companion object {
        val MIN_WITHDRAW_RUPEES: BigDecimal = BigDecimal("50")
    }

    suspend fun withdraw(
        userId: UUID,
        req: GoldWithdrawRequest
    ): Result<GoldWithdrawResponse, GoldWithdrawException> {

        if (req.amountRupees < MIN_WITHDRAW_RUPEES) {
            return Result.failure(MinimumWithdrawException())
        }

        val wallet = goldWalletRepo.findByUserId(userId)
        if (wallet == null || wallet.totalGrams <= BigDecimal.ZERO) {
            return Result.failure(InsufficientGoldBalanceException(BigDecimal.ZERO, req.amountRupees))
        }

        // Current gold sell rate fetch karo (withdraw = sell)
        val rateResult = investService.getDisplayRates()
        val goldRate = when (rateResult) {
            is Result.Success -> rateResult.value.goldSellRate
            is Result.Failure -> {
                log.error("Failed to fetch gold rate for withdrawal, userId={}: {}", userId, rateResult.error.message)
                return Result.failure(GoldRateFetchFailedException())
            }
        }

        val goldGramsRequired = req.amountRupees.divide(goldRate, 6, RoundingMode.HALF_UP)
        val availableRupeesValue = wallet.totalGrams.multiply(goldRate).setScale(2, RoundingMode.HALF_UP)

        if (wallet.totalGrams < goldGramsRequired) {
            return Result.failure(InsufficientGoldBalanceException(availableRupeesValue, req.amountRupees))
        }

        return txOperator.executeAndAwait {
            // 1. Gold wallet se grams deduct karo
            val rowsAffected = goldWalletRepo.atomicGramsUpdate(userId, goldGramsRequired.negate())
            if (rowsAffected == 0) {
                return@executeAndAwait Result.failure(InsufficientGoldBalanceException(availableRupeesValue, req.amountRupees))
            }

            // 2. Withdraw request log karo
            goldWithdrawRepo.save(
                GoldWithdrawRequestEntity(
                    userId = userId,
                    amountRupees = req.amountRupees,
                    goldGramsDeducted = goldGramsRequired,
                    goldRateAtWithdraw = goldRate,
                    status = "COMPLETED"
                )
            )

            // 3. App wallet (NBFC) me cash credit karo
            val creditResult = walletService.credit(
                userId = userId,
                walletType = "NBFC",
                amount = req.amountRupees,
                referenceType = "GOLD_WITHDRAW",
                description = "Gold withdrawal — ${goldGramsRequired}g converted to cash",
                idempotencyKey = "gold_withdraw_${userId}_${System.currentTimeMillis()}"
            )
            if (creditResult is Result.Failure) {
                log.error("Wallet credit failed during gold withdraw for userId={}: {}", userId, creditResult.error.message)
                return@executeAndAwait Result.failure(GoldRateFetchFailedException()) // fallback, txn rollback ho jayega
            }

            val updatedWallet = goldWalletRepo.findByUserId(userId)!!

            log.info(
                "Gold withdraw completed: userId={}, amountRupees=₹{}, goldGramsDeducted={}, remainingGrams={}",
                userId, req.amountRupees, goldGramsRequired, updatedWallet.totalGrams
            )

            Result.success(
                GoldWithdrawResponse(
                    userId = userId,
                    amountRupees = req.amountRupees,
                    goldGramsDeducted = goldGramsRequired,
                    remainingGoldGrams = updatedWallet.totalGrams
                )
            )
        }!!
    }
}