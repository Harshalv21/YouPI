package `in`.youpi.core

import java.math.BigDecimal
import java.util.UUID

// ── Wallet debit port ──
//
// Same reasoning as WalletCreditPort.kt -- lives in shared/core so a
// future caller (e.g. RechargeService, for "pay recharge from wallet")
// can depend on just this interface instead of the concrete
// modules/wallet module, avoiding a circular Gradle dependency
// (modules/wallet already depends on modules/payment).
//
// NOT YET WIRED into RechargeService as of this commit -- only
// WalletService's implementation exists so far. The "spend from
// wallet" recharge flow (createOrder() branching on PaymentMode.WALLET,
// plus extracting the A1Topup delivery trigger so both the Cashfree
// webhook path and this synchronous debit path can call it) is a
// separate, deliberately deferred step -- see chat history.
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
    data class Rejected(val reason: WalletDebitRejectionReason, val message: String) : WalletDebitOutcome()
}

enum class WalletDebitRejectionReason {
    SERVICE_NOT_ALLOWED,
    INSUFFICIENT_BALANCE,
    WALLET_NOT_FOUND
}