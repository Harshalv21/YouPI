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
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface RechargeOrderRepository : CoroutineCrudRepository<RechargeOrderEntity, UUID> {
    suspend fun findByIdempotencyKey(idempotencyKey: String): RechargeOrderEntity?

    // Needed by the Razorpay webhook handler -- the webhook only knows the
    // razorpay_order_id, not our internal recharge order UUID.
    suspend fun findByRazorpayOrderId(razorpayOrderId: String): RechargeOrderEntity?

    // Custom insert with explicit ::jsonb cast — Spring Data's auto-generated
    // save() can't reliably bind a plain String into a JSONB column without
    // a registered converter, and a global converter caused type mismatches
    // on unrelated VARCHAR columns (see MPIN verify bug). This scopes the
    // JSONB handling to just this one column.
    @Query("""
        INSERT INTO recharge_orders 
        (user_id, mobile_number, operator, circle, plan_id, plan_amount, plan_details, 
         payment_mode, emi_months, emi_amount, status, razorpay_order_id, gold_auto_invest, 
         idempotency_key, plan_validity_days)
        VALUES 
        (:userId, :mobileNumber, :operator, :circle, :planId, :planAmount, CAST(:planDetails AS jsonb),
         :paymentMode, :emiMonths, :emiAmount, :status, :razorpayOrderId, :goldAutoInvest, 
         :idempotencyKey, :planValidityDays)
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
        planValidityDays: Int?
    ): RechargeOrderEntity

    // Separate, tiny update -- only fires on confirmed RECHARGE_SUCCESS, so
    // it's cleaner as its own statement than adding two more always-present
    // params to the already-large updateAfterConfirm call.
    @Query("UPDATE recharge_orders SET expiry_date = :expiryDate WHERE id = :id")
    suspend fun setExpiryDate(id: UUID, expiryDate: LocalDate)

    // Powers the home screen "Active Recharge" card -- most recent
    // successful recharge for this user that hasn't expired yet. Only one
    // row ever matters here (LIMIT 1); if the user has multiple numbers
    // recharged, this shows whichever is most recently active -- fine for
    // this version since the app only has one primary recharge flow, not
    // per-number tracking.
    @Query("""
        SELECT * FROM recharge_orders 
        WHERE user_id = :userId 
          AND status = 'RECHARGE_SUCCESS' 
          AND expiry_date >= CURRENT_DATE
        ORDER BY expiry_date DESC
        LIMIT 1
    """)
    suspend fun findActiveRecharge(userId: UUID): RechargeOrderEntity?

    // Same reasoning — a1topup_raw_response is JSONB, needs explicit cast on write.
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