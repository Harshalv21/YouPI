package `in`.youpi.payment.repository

// ── MOVED from modules/payment to shared/core ──
//
// Reason: modules/gold already depends on modules/wallet
// (GoldWithdrawService uses WalletService), and modules/recharge already
// depends on modules/gold, and modules/payment already depends on
// modules/recharge. That means modules/payment TRANSITIVELY already
// depended on modules/wallet before any of this Wallet MVP work started:
//   payment -> recharge -> gold -> wallet
//
// When WalletService needed PaymentOrderRepository (to persist WALLET_TOPUP
// orders into the existing payment_orders table), adding
// modules/wallet -> modules/payment as a direct Gradle dependency closed
// the loop:
//   wallet -> payment -> recharge -> gold -> wallet
// ...which Gradle correctly refuses to build (circular task dependency).
//
// Fix: move the entity + repository here, to shared/core, which every
// module in this chain already depends on. Package name is UNCHANGED
// (still `in.youpi.payment.repository`) so no import statement anywhere
// else in the codebase needs to change -- only this file's physical
// module location moved.
//
// modules/wallet's build.gradle.kts should NOT have
// api(project(":modules:payment")) anymore -- shared/core already
// provides this.

import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import java.time.Instant
import java.util.UUID

@Table("payment_orders")
data class PaymentOrderEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val razorpayOrderId: String,
    val razorpayPaymentId: String? = null,
    val razorpaySignature: String? = null,
    val amountPaise: Long,
    val currency: String = "INR",
    val purpose: String,
    val referenceId: UUID? = null,
    val status: String = "CREATED",
    val webhookEvent: String? = null,
    val webhookPayload: String? = null,
    val idempotencyKey: String,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface PaymentOrderRepository : CoroutineCrudRepository<PaymentOrderEntity, UUID> {
    suspend fun findByRazorpayOrderId(razorpayOrderId: String): PaymentOrderEntity?
    suspend fun findByIdempotencyKey(idempotencyKey: String): PaymentOrderEntity?

    @Query("SELECT * FROM payment_orders WHERE user_id = :userId ORDER BY created_at DESC LIMIT :limit OFFSET :offset")
    suspend fun findByUserId(userId: UUID, limit: Int = 20, offset: Int = 0): List<PaymentOrderEntity>

    // ← NAYA: wallet topup sweeper (missed-webhook safety net) ke liye
    suspend fun findByPurposeAndStatus(purpose: String, status: String): List<PaymentOrderEntity>

    // webhook_payload JSONB column me explicit cast — same reasoning as
    // recharge_orders.plan_details (see RechargeOrderRepository).
    @Query("""
        UPDATE payment_orders
        SET razorpay_payment_id = :razorpayPaymentId,
            status = :status,
            webhook_event = :webhookEvent,
            webhook_payload = CAST(:webhookPayload AS jsonb),
            updated_at = NOW()
        WHERE id = :id
        RETURNING *
    """)
    suspend fun updateWebhookCaptured(
        id: UUID,
        razorpayPaymentId: String?,
        status: String,
        webhookEvent: String?,
        webhookPayload: String
    ): PaymentOrderEntity
}