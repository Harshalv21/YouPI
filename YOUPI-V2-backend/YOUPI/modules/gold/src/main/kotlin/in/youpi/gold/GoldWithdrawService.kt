package `in`.youpi.gold

import `in`.youpi.core.BaseException
import `in`.youpi.core.Result
import `in`.youpi.wallet.service.WalletService
import org.slf4j.LoggerFactory
import org.springframework.r2dbc.connection.R2dbcTransactionManager
import org.springframework.stereotype.Service
import org.springframework.transaction.reactive.TransactionalOperator
import org.springframework.transaction.reactive.executeAndAwait
import java.math.BigDecimal
import java.util.UUID

// ── DTOs ──

data class GoldWithdrawRequest(
    val amountRupees: BigDecimal
)

data class GoldWithdrawResponse(
    val userId: UUID,
    val amountRupees: BigDecimal,
    val remainingBalanceRupees: BigDecimal,
    val remainingCoinCount: Int
)

// ── Exceptions ──

sealed class GoldWithdrawException(code: String, message: String, httpStatus: Int = 400)
    : BaseException(code, message) { override val httpStatus: Int = httpStatus }

class MinimumWithdrawException : GoldWithdrawException(
    "MIN_WITHDRAW", "Minimum withdrawal amount is ₹50", 400
)

class InsufficientGoldBalanceException(val availableRupees: BigDecimal, val requiredRupees: BigDecimal) : GoldWithdrawException(
    "INSUFFICIENT_GOLD_BALANCE", "Insufficient balance: available ₹$availableRupees, required ₹$requiredRupees", 402
)

@Service
class GoldWithdrawService(
    private val goldWalletRepo: GoldWalletRepository,
    private val goldWithdrawRepo: GoldWithdrawRequestRepository,
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
        if (wallet == null || wallet.balanceRupees < req.amountRupees) {
            val available = wallet?.balanceRupees ?: BigDecimal.ZERO
            return Result.failure(InsufficientGoldBalanceException(available, req.amountRupees))
        }

        return txOperator.executeAndAwait {
            // 1. Wallet se rupees deduct karo (atomic, balance check DB level pe bhi)
            val deductedUserId = goldWalletRepo.deductBalance(userId, req.amountRupees)
            if (deductedUserId == null) {
                return@executeAndAwait Result.failure(
                    InsufficientGoldBalanceException(wallet.balanceRupees, req.amountRupees)
                )
            }

            // 2. Withdraw request log karo
            goldWithdrawRepo.save(
                GoldWithdrawRequestEntity(
                    userId = userId,
                    amountRupees = req.amountRupees,
                    status = "COMPLETED"
                )
            )

            // 3. App wallet (NBFC) me cash credit karo
            val creditResult = walletService.credit(
                userId = userId,
                walletType = "NBFC",
                amount = req.amountRupees,
                referenceType = "GOLD_WITHDRAW",
                description = "Gold coin withdrawal — ₹${req.amountRupees} converted to cash",
                idempotencyKey = "gold_withdraw_${userId}_${System.currentTimeMillis()}"
            )
            if (creditResult is Result.Failure) {
                log.error("Wallet credit failed during gold withdraw for userId={}: {}", userId, creditResult.error.message)
                return@executeAndAwait Result.failure(
                    InsufficientGoldBalanceException(wallet.balanceRupees, req.amountRupees)
                ) // fallback error, txn rollback ho jayega
            }

            val updatedWallet = goldWalletRepo.findByUserId(userId)!!

            log.info(
                "Gold withdraw completed: userId={}, amountRupees=₹{}, remainingBalance=₹{}",
                userId, req.amountRupees, updatedWallet.balanceRupees
            )

            Result.success(
                GoldWithdrawResponse(
                    userId = userId,
                    amountRupees = req.amountRupees,
                    remainingBalanceRupees = updatedWallet.balanceRupees,
                    remainingCoinCount = updatedWallet.coinCount
                )
            )
        }!!
    }
}