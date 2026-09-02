package `in`.youpi.recharge.repository

import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

@Table("recharge_orders")
data class RechargeOrderEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    // ← DTH orders reuse this same column for the subscriber/VC number --
    // no separate subscriberNumber column was added. Every read site that
    // shows this value already just displays "the number recharged",
    // which is correct for DTH too (shows the VC number instead of a
    // mobile number).
    val mobileNumber: String,
    val operator: String,
    val circle: String? = null,
    val planId: String? = null,
    val planAmount: BigDecimal,
    val planDetails: String = "{}",
    val paymentMode: String,
    val emiMonths: Short? = null,
    val emiAmount: BigDecimal? = null,
    val status: String = "INITIATED",
    val razorpayOrderId: String? = null,
    val razorpayPaymentId: String? = null,
    val a1topupTxnId: String? = null,
    val a1topupStatus: String? = null,
    val a1topupRawResponse: String? = null,
    val failureReason: String? = null,
    val planValidityDays: Int? = null,
    val expiryDate: LocalDate? = null,
    val goldAutoInvest: Boolean = false,
    val goldTxnId: UUID? = null,
    val idempotencyKey: String,
    val walletAmount: BigDecimal? = null,
    val gatewayAmount: BigDecimal? = null,
    // ← NEW: "MOBILE" (default, every existing row) or "DTH". Read by
    // RechargeService.handleWebhookCaptured() (guards mobile delivery
    // path against DTH orders), RechargeService.resolveA1TopupOutcome()
    // (picks the correct gold-reward eligibility threshold), and
    // DthRechargeService (filters to only its own orders).
    val serviceType: String = "MOBILE",
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface RechargeOrderRepository : CoroutineCrudRepository<RechargeOrderEntity, UUID> {
    suspend fun findByIdempotencyKey(idempotencyKey: String): RechargeOrderEntity?

    suspend fun findByRazorpayOrderId(razorpayOrderId: String): RechargeOrderEntity?

    @Query("SELECT * FROM recharge_orders WHERE payment_mode = :paymentMode AND status = :status")
    suspend fun findByPaymentModeAndStatus(paymentMode: String, status: String): List<RechargeOrderEntity>

    // ← CHANGED: wallet_amount, gateway_amount, service_type columns added
    // to the INSERT (wallet_amount/gateway_amount nullable -- NULL for
    // every payment mode except SPLIT; service_type defaults to 'MOBILE').
    @Query("""
        INSERT INTO recharge_orders 
        (user_id, mobile_number, operator, circle, plan_id, plan_amount, plan_details, 
         payment_mode, emi_months, emi_amount, status, razorpay_order_id, gold_auto_invest, 
         idempotency_key, plan_validity_days, wallet_amount, gateway_amount, service_type)
        VALUES 
        (:userId, :mobileNumber, :operator, :circle, :planId, :planAmount, CAST(:planDetails AS jsonb),
         :paymentMode, :emiMonths, :emiAmount, :status, :razorpayOrderId, :goldAutoInvest, 
         :idempotencyKey, :planValidityDays, :walletAmount, :gatewayAmount, :serviceType)
        RETURNING *
    """)
    suspend fun insertOrder(
        userId: UUID,
        mobileNumber: String,
        operator: String,
        circle: String?,
        planId: String?,
        planAmount: BigDecimal,
        planDetails: String,
        paymentMode: String,
        emiMonths: Short?,
        emiAmount: BigDecimal?,
        status: String,
        razorpayOrderId: String?,
        goldAutoInvest: Boolean,
        idempotencyKey: String,
        planValidityDays: Int?,
        walletAmount: BigDecimal? = null,
        gatewayAmount: BigDecimal? = null,
        // ← NEW param, default "MOBILE" so every pre-DTH call site keeps
        // compiling unchanged and lands as MOBILE.
        serviceType: String = "MOBILE"
    ): RechargeOrderEntity

    @Query("UPDATE recharge_orders SET expiry_date = :expiryDate WHERE id = :id")
    suspend fun setExpiryDate(id: UUID, expiryDate: LocalDate)

    @Query("""
        SELECT * FROM recharge_orders 
        WHERE user_id = :userId 
          AND status = 'RECHARGE_SUCCESS' 
          AND expiry_date >= (NOW() AT TIME ZONE 'Asia/Kolkata')::date
        ORDER BY expiry_date DESC
        LIMIT 1
    """)
    suspend fun findActiveRecharge(userId: UUID): RechargeOrderEntity?

    @Query("""
        SELECT * FROM recharge_orders 
        WHERE user_id = :userId 
          AND status = 'RECHARGE_SUCCESS' 
          AND expiry_date >= (NOW() AT TIME ZONE 'Asia/Kolkata')::date
        ORDER BY expiry_date ASC
        LIMIT 10
    """)
    suspend fun findActiveRecharges(userId: UUID): List<RechargeOrderEntity>

    @Query("""
        UPDATE recharge_orders 
        SET status = :status, 
            razorpay_payment_id = :razorpayPaymentId,
            a1topup_status = :a1topupStatus,
            a1topup_raw_response = CAST(:a1topupRawResponse AS jsonb),
            gold_auto_invest = :goldAutoInvest,
            gold_txn_id = :goldTxnId,
            failure_reason = :failureReason,
            updated_at = NOW()
        WHERE id = :id
        RETURNING *
    """)
    suspend fun updateAfterConfirm(
        id: UUID,
        status: String,
        razorpayPaymentId: String?,
        a1topupStatus: String?,
        a1topupRawResponse: String?,
        goldAutoInvest: Boolean,
        goldTxnId: UUID?,
        failureReason: String? = null
    ): RechargeOrderEntity

    // ← NEW: identical to updateAfterConfirm() above, except the WHERE
    // clause also requires the row's CURRENT status to still match
    // expectedCurrentStatus. This is a compare-and-swap: if two callers
    // race to resolve the same order (e.g. a duplicate Razorpay webhook
    // delivery, or a webhook and the reconciliation job overlapping),
    // only the first UPDATE to actually run matches the WHERE clause and
    // returns a row -- the second one matches zero rows (because the
    // first already changed the status) and gets back null.
    //
    // Callers use this null/non-null result as the single source of
    // truth for "did I win the race to resolve this order" and gate
    // reward-crediting + push-notification dispatch on it, instead of
    // relying on the separate read-then-branch status check that ran
    // earlier (which is NOT atomic with this write and cannot by itself
    // prevent two concurrent calls from both proceeding).
    //
    // Gold Coin crediting has its own independent safety net regardless
    // (gold_reward_ledger's UNIQUE(recharge_txn_id) constraint via
    // insertIfNotExists) -- this CAS is specifically what push
    // notification was missing, since it has no ledger of its own.
    //
    // The unmodified updateAfterConfirm() above is left exactly as-is
    // and keeps serving every call site that doesn't gate a
    // reward/notification decision on the transition (e.g. the SPLIT
    // abandoned-checkout refund path), so this is additive, not a
    // replacement.
    @Query("""
        UPDATE recharge_orders 
        SET status = :status, 
            razorpay_payment_id = :razorpayPaymentId,
            a1topup_status = :a1topupStatus,
            a1topup_raw_response = CAST(:a1topupRawResponse AS jsonb),
            gold_auto_invest = :goldAutoInvest,
            gold_txn_id = :goldTxnId,
            failure_reason = :failureReason,
            updated_at = NOW()
        WHERE id = :id AND status = :expectedCurrentStatus
        RETURNING *
    """)
    suspend fun updateAfterConfirmIfStatus(
        id: UUID,
        expectedCurrentStatus: String,
        status: String,
        razorpayPaymentId: String?,
        a1topupStatus: String?,
        a1topupRawResponse: String?,
        goldAutoInvest: Boolean,
        goldTxnId: UUID?,
        failureReason: String? = null
    ): RechargeOrderEntity?

    @Query("SELECT * FROM recharge_orders WHERE user_id = :userId ORDER BY created_at DESC LIMIT :limit OFFSET :offset")
    suspend fun findByUserId(userId: UUID, limit: Int = 20, offset: Int = 0): List<RechargeOrderEntity>

    @Query("SELECT * FROM recharge_orders WHERE status = :status")
    suspend fun findByStatus(status: String): List<RechargeOrderEntity>

    @Query("UPDATE recharge_orders SET status = :status, a1topup_txn_id = :txnId, a1topup_status = :a1Status, updated_at = NOW() WHERE id = :id")
    suspend fun updateRechargeStatus(id: UUID, status: String, txnId: String?, a1Status: String?)
}

@Table("recharge_emi_schedules")
data class RechargeEmiEntity(
    @Id val id: UUID? = null,
    val rechargeId: UUID,
    val userId: UUID,
    val instalmentNo: Short,
    val dueDate: LocalDate,
    val amount: BigDecimal,
    val status: String = "PENDING",
    val paidAt: Instant? = null,
    val razorpayPaymentId: String? = null,
    val createdAt: Instant = Instant.now()
)

interface RechargeEmiRepository : CoroutineCrudRepository<RechargeEmiEntity, UUID> {
    suspend fun findAllByRechargeId(rechargeId: UUID): List<RechargeEmiEntity>

    @Query("SELECT * FROM recharge_emi_schedules WHERE user_id = :userId AND status = :status ORDER BY due_date")
    suspend fun findByUserIdAndStatus(userId: UUID, status: String): List<RechargeEmiEntity>
}