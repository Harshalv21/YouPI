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
    val goldAutoInvest: Boolean = false,
    val goldTxnId: UUID? = null,
    val idempotencyKey: String,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface RechargeOrderRepository : CoroutineCrudRepository<RechargeOrderEntity, UUID> {
    suspend fun findByIdempotencyKey(idempotencyKey: String): RechargeOrderEntity?

    // Custom insert with explicit ::jsonb cast — Spring Data's auto-generated
    // save() can't reliably bind a plain String into a JSONB column without
    // a registered converter, and a global converter caused type mismatches
    // on unrelated VARCHAR columns (see MPIN verify bug). This scopes the
    // JSONB handling to just this one column.
    @Query("""
        INSERT INTO recharge_orders 
        (user_id, mobile_number, operator, circle, plan_id, plan_amount, plan_details, 
         payment_mode, emi_months, emi_amount, status, razorpay_order_id, gold_auto_invest, idempotency_key)
        VALUES 
        (:userId, :mobileNumber, :operator, :circle, :planId, :planAmount, CAST(:planDetails AS jsonb),
         :paymentMode, :emiMonths, :emiAmount, :status, :razorpayOrderId, :goldAutoInvest, :idempotencyKey)
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
        idempotencyKey: String
    ): RechargeOrderEntity

    // Same reasoning — a1topup_raw_response is JSONB, needs explicit cast on write.
    @Query("""
        UPDATE recharge_orders 
        SET status = :status, 
            razorpay_payment_id = :razorpayPaymentId,
            a1topup_status = :a1topupStatus,
            a1topup_raw_response = CAST(:a1topupRawResponse AS jsonb),
            gold_auto_invest = :goldAutoInvest,
            gold_txn_id = :goldTxnId,
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
        goldTxnId: UUID?
    ): RechargeOrderEntity

    suspend fun findById(id: UUID): RechargeOrderEntity?

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
