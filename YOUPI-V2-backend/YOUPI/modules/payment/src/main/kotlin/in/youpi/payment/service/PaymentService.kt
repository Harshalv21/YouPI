package `in`.youpi.payment.service

import `in`.youpi.core.Result
import `in`.youpi.events.PubSubPublisher
import `in`.youpi.payment.domain.*
import `in`.youpi.payment.repository.PaymentOrderEntity
import `in`.youpi.payment.repository.PaymentOrderRepository
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.readValue
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.time.Instant
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

@Service
class PaymentService(
    private val paymentRepo: PaymentOrderRepository,
    private val pubSubPublisher: PubSubPublisher,          // ← TODO replace: Pub/Sub event publish
    private val objectMapper: ObjectMapper,                // ← webhook JSON parse ke liye
    @Value("\${youpi.razorpay.key-id:}") private val razorpayKeyId: String,
    @Value("\${youpi.razorpay.key-secret:}") private val razorpayKeySecret: String,
    @Value("\${youpi.razorpay.webhook-secret:}") private val webhookSecret: String
) {

    private val log = LoggerFactory.getLogger(javaClass)

    // ── Create Razorpay Order ──

    suspend fun createOrder(userId: UUID, req: CreatePaymentOrderRequest): Result<PaymentOrderResponse, PaymentException> {
        val existing = paymentRepo.findByIdempotencyKey(req.idempotencyKey)
        if (existing != null) {
            return Result.success(toResponse(existing))
        }

        val amountPaise = req.amount.multiply(java.math.BigDecimal(100)).toLong()

        // TODO: Real Razorpay API call — replace stub with Razorpay SDK
        val razorpayOrderId = "order_${UUID.randomUUID().toString().take(14)}"

        val order = paymentRepo.save(
            PaymentOrderEntity(
                userId = userId,
                razorpayOrderId = razorpayOrderId,
                amountPaise = amountPaise,
                purpose = req.purpose.name,
                referenceId = req.referenceId,
                idempotencyKey = req.idempotencyKey
            )
        )

        log.info("Payment order created: orderId={}, razorpay={}, ₹{}", order.id, razorpayOrderId, req.amount)
        return Result.success(toResponse(order))
    }

    // ── Verify Client-Side Payment ──

    suspend fun verifyPayment(userId: UUID, req: VerifyPaymentRequest): Result<PaymentOrderResponse, PaymentException> {
        val order = paymentRepo.findByRazorpayOrderId(req.razorpayOrderId)
            ?: return Result.failure(PaymentOrderNotFoundException(req.razorpayOrderId))

        // ← ownership check — doosre user ka order capture nahi kar sakte
        if (order.userId != userId) {
            return Result.failure(PaymentOrderNotFoundException(req.razorpayOrderId))
        }

        if (order.status == "CAPTURED") {
            return Result.failure(PaymentAlreadyCaptured(order.id!!))
        }

        // Verify HMAC-SHA256 signature
        val payload = "${req.razorpayOrderId}|${req.razorpayPaymentId}"
        if (!verifyHmacSignature(payload, req.razorpaySignature, razorpayKeySecret)) {
            return Result.failure(PaymentSignatureInvalidException())
        }

        val updated = paymentRepo.save(
            order.copy(
                razorpayPaymentId = req.razorpayPaymentId,
                razorpaySignature = req.razorpaySignature,
                status = "CAPTURED",
                updatedAt = Instant.now()
            )
        )

        log.info("Payment captured: orderId={}, paymentId={}, purpose={}", updated.id, req.razorpayPaymentId, updated.purpose)

        // ← TODO was here — ab Pub/Sub pe event publish hoga
        publishPaymentCapturedEvent(updated)

        return Result.success(toResponse(updated))
    }

    // ── Webhook Handler (Idempotent) ──

    suspend fun handleWebhook(rawPayload: String, signature: String): Boolean {
        if (!verifyHmacSignature(rawPayload, signature, webhookSecret)) {
            log.warn("Webhook signature verification failed")
            return false
        }

        // ← TODO was here — ab webhook payload parse hoga
        return try {
            val parsed = objectMapper.readValue<Map<String, Any>>(rawPayload)
            val event = parsed["event"] as? String ?: return true

            when (event) {
                "payment.captured" -> handleWebhookCaptured(parsed)
                "payment.failed"   -> handleWebhookFailed(parsed)
                else -> {
                    log.info("Unhandled webhook event: {}", event)
                    true
                }
            }
        } catch (e: Exception) {
            log.error("Webhook parse error", e)
            false
        }
    }

    private suspend fun handleWebhookCaptured(parsed: Map<String, Any>): Boolean {
        val paymentObj = (parsed["payload"] as? Map<*, *>)
            ?.get("payment") as? Map<*, *>
            ?: return true

        val entity = paymentObj["entity"] as? Map<*, *> ?: return true
        val razorpayOrderId = entity["order_id"] as? String ?: return true
        val razorpayPaymentId = entity["id"] as? String ?: return true

        val order = paymentRepo.findByRazorpayOrderId(razorpayOrderId) ?: run {
            log.warn("Webhook: order not found for razorpayOrderId={}", razorpayOrderId)
            return true  // idempotent — naya order nahi banate webhook se
        }

        // Idempotency — already captured toh no-op
        if (order.status == "CAPTURED") {
            log.info("Webhook: payment already captured, skipping orderId={}", order.id)
            return true
        }

        val updated = paymentRepo.save(
            order.copy(
                razorpayPaymentId = razorpayPaymentId,
                status = "CAPTURED",
                webhookEvent = "payment.captured",
                webhookPayload = razorpayOrderId,
                updatedAt = Instant.now()
            )
        )

        log.info("Webhook: payment captured orderId={}, paymentId={}", updated.id, razorpayPaymentId)
        publishPaymentCapturedEvent(updated)
        return true
    }

    private suspend fun handleWebhookFailed(parsed: Map<String, Any>): Boolean {
        val paymentObj = (parsed["payload"] as? Map<*, *>)
            ?.get("payment") as? Map<*, *>
            ?: return true

        val entity = paymentObj["entity"] as? Map<*, *> ?: return true
        val razorpayOrderId = entity["order_id"] as? String ?: return true

        val order = paymentRepo.findByRazorpayOrderId(razorpayOrderId) ?: return true

        if (order.status == "FAILED") return true

        paymentRepo.save(
            order.copy(
                status = "FAILED",
                webhookEvent = "payment.failed",
                updatedAt = Instant.now()
            )
        )

        log.info("Webhook: payment failed orderId={}", order.id)
        return true
    }

    // ← Yeh function wallet credit trigger karta hai Pub/Sub ke through
    private suspend fun publishPaymentCapturedEvent(order: PaymentOrderEntity) {
        try {
            pubSubPublisher.publish(
                "payment-captured",
                mapOf(
                    "orderId"    to order.id.toString(),
                    "userId"     to order.userId.toString(),
                    "amountPaise" to order.amountPaise,
                    "purpose"    to order.purpose,
                    "referenceId" to (order.referenceId?.toString() ?: "")
                )
            )
            log.info("payment-captured event published for orderId={}", order.id)
        } catch (e: Exception) {
            // Non-fatal — webhook will retry; wallet credited via subscriber
            log.error("Failed to publish payment-captured event for orderId={}: {}", order.id, e.message)
        }
    }

    // ── HMAC Verification ──

    private fun verifyHmacSignature(payload: String, expectedSignature: String, secret: String): Boolean {
        if (secret.isBlank()) {
            log.warn("HMAC secret not configured — skipping verification (dev mode)")
            return true
        }

        return try {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(secret.toByteArray(), "HmacSHA256"))
            val computedHex = mac.doFinal(payload.toByteArray())
                .joinToString("") { "%02x".format(it) }
            computedHex.equals(expectedSignature, ignoreCase = true)
        } catch (e: Exception) {
            log.error("HMAC verification error", e)
            false
        }
    }

    // ── Helpers ──

    private fun toResponse(entity: PaymentOrderEntity) = PaymentOrderResponse(
        orderId = entity.id!!,
        razorpayOrderId = entity.razorpayOrderId,
        amount = java.math.BigDecimal(entity.amountPaise)
            .divide(java.math.BigDecimal(100), 2, java.math.RoundingMode.HALF_EVEN),
        status = entity.status,
        keyId = razorpayKeyId
    )
}