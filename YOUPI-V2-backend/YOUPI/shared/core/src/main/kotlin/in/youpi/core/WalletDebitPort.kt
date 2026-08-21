package `in`.youpi.core

import java.math.BigDecimal
import java.util.UUID

// ── Wallet debit port ──
//
// Same reasoning as WalletCreditPort.kt -- lives in shared/core so a
// caller (e.g. RechargeService, for "pay recharge from wallet") can
// depend on just this interface instead of the concrete modules/wallet
// module, avoiding a circular Gradle dependency.
interface WalletDebitPort {

    /**
     * Checks the service_code allowlist, then debits the wallet if
     * allowed and funds are sufficient. Idempotent -- safe to retry with
     * the same idempotencyKey (WalletService.debit() dedupes via ledger
     * lookup).
     */
    suspend fun debitForService(
        userId: UUID,
        walletType: String,
        amount: BigDecimal,
        serviceCode: String,
        referenceId: UUID?,
        description: String?,
        idempotencyKey: String
    ): WalletDebitOutcome
}

sealed class WalletDebitOutcome {
    data class Success(val walletId: UUID, val newBalance: BigDecimal) : WalletDebitOutcome()

    // ← CHANGED: available/required add kiya taaki caller (RechargeService)
    // ke paas exact numbers ho structured exception banane ke liye --
    // pehle sirf reason+message text tha.
    data class Rejected(
        val reason: WalletDebitRejectionReason,
        val message: String,
        val available: BigDecimal? = null,
        val required: BigDecimal? = null
    ) : WalletDebitOutcome()
}

enum class WalletDebitRejectionReason {
    SERVICE_NOT_ALLOWED,
    INSUFFICIENT_BALANCE,
    WALLET_NOT_FOUND
}