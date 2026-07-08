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
