package `in`.youpi.core

import java.util.UUID

// ── Wallet credit port ──
//
// Why this interface exists here (shared/core) instead of PaymentService
// calling WalletService directly:
//
// modules/wallet needs modules/payment (PaymentOrderRepository) to persist
// wallet top-up orders into the existing `payment_orders` table
// (purpose='WALLET_TOPUP' -- reuses V5's table, see V17 migration).
// That means: wallet -> payment (compile-time module dependency).
//
// If modules/payment also depended on modules/wallet directly (to call
// WalletService.credit() from the Cashfree webhook handler), that would
// be a circular Gradle module dependency (payment -> wallet -> payment),
// which does not compile.
//
// Fix: PaymentService depends only on this interface (lives in
// shared/core, which both modules already depend on). WalletService
// implements it. Spring wires the real bean at runtime via the app
// module's classpath -- no compile-time link needed between payment
// and wallet themselves.
interface WalletCreditPort {

    /**
     * Credits a wallet after a Cashfree top-up order is confirmed CAPTURED
     * via webhook. Idempotent -- safe to call more than once for the same
     * idempotencyKey (webhook retries), because the underlying
     * WalletService.credit() dedupes on idempotencyKey via ledger lookup.
     *
     * @return true if the wallet was found and credit() was invoked
     *   (whether this call actually moved money or was a no-op replay);
     *   false if no matching wallet was found for userId/walletType
     *   (defensive -- should not normally happen for a WALLET_TOPUP order).
     */
    suspend fun creditWalletTopup(
        userId: UUID,
        walletType: String,
        amountPaise: Long,
        idempotencyKey: String,
        cashfreeOrderId: String
    ): Boolean

    /**
     * Generic credit-back -- used when a WALLET-paid purchase (e.g. a
     * recharge) fails downstream after the wallet was already debited, and
     * the money needs to go back. Distinct from creditWalletTopup() (which
     * is specifically "money coming IN from Cashfree") -- this is "money
     * going back to a wallet that was debited for something that didn't
     * complete." Idempotent -- safe to retry with the same idempotencyKey.
     */
    suspend fun reverseDebit(
        userId: UUID,
        walletType: String,
        amountPaise: Long,
        referenceType: String,
        referenceId: UUID?,
        description: String?,
        idempotencyKey: String
    ): Boolean
}