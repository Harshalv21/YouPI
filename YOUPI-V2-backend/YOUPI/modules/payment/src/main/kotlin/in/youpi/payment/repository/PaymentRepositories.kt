package `in`.youpi.payment.repository

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
}
