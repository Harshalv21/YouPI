package `in`.youpi.payment.service

import `in`.youpi.core.Result
import `in`.youpi.core.WalletCreditPort
import `in`.youpi.core.razorpay.RazorpayClient
import `in`.youpi.core.razorpay.RazorpayOrderCreationException
import `in`.youpi.events.PubSubPublisher
import `in`.youpi.payment.domain.*
import `in`.youpi.payment.repository.PaymentOrderEntity
import `in`.youpi.payment.repository.PaymentOrderRepository
import `in`.youpi.recharge.service.DthRechargeService
import `in`.youpi.recharge.service.RechargeService
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
    private val pubSubPublisher: PubSubPublisher,
    private val objectMapper: ObjectMapper,
    private val razorpayClient: RazorpayClient,
    private val rechargeService: RechargeService,          // ← webhook.captured → mobile recharge completion
    // ← NEW: webhook.captured → DTH recharge completion. Tried AFTER
    // rechargeService returns false (its serviceType guard now rejects
    // non-MOBILE orders -- see RechargeService.handleWebhookCaptured()).
    private val dthRechargeService: DthRechargeService,
    private val walletCreditPort: WalletCreditPort,
    @Value("\${youpi.razorpay.key-id:}") private val razorpayKeyId: String,
    @Value("\${youpi.razorpay.key-secret:}") private val razorpayKeySecret: String,
    @Value("\${youpi.razorpay.webhook-secret:}") private val webhookSecret: String
) {

    private val log = LoggerFactory.getLogger(javaClass)

    // ── Create Razorpay Order ── -- UNCHANGED
    suspend fun createOrder(userId: UUID, req: CreatePaymentOrderRequest): Result<PaymentOrderResponse, PaymentException> {
        val existing = paymentRepo.findByIdempotencyKey(req.idempotencyKey)
        if (existing != null) {
            return Result.success(toResponse(existing))
        }

        val amountPaise = req.amount.multiply(java.math.BigDecimal(100)).toLong()

        val razorpayOrderId = try {
            razorpayClient.createOrder(
                amountPaise = amountPaise,
                receipt = req.idempotencyKey,
                notes = mapOf("purpose" to req.purpose.name, "userId" to userId.toString())
            ).id
        } catch (e: RazorpayOrderCreationException) {
            log.error("Razorpay order creation failed for user={}: {}", userId, e.message)
            return Result.failure(PaymentOrderCreationFailedException(e.message ?: "unknown error"))
        }

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

    // ── Verify Client-Side Payment ── -- UNCHANGED
    suspend fun verifyPayment(userId: UUID, req: VerifyPaymentRequest): Result<PaymentOrderResponse, PaymentException> {
        val order = paymentRepo.findByRazorpayOrderId(req.razorpayOrderId)
            ?: return Result.failure(PaymentOrderNotFoundException(req.razorpayOrderId))

        if (order.userId != userId) {
            return Result.failure(PaymentOrderNotFoundException(req.razorpayOrderId))
        }

        if (order.status == "CAPTURED") {
            return Result.failure(PaymentAlreadyCaptured(order.id!!))
        }

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

        log.info("Payment captured (client-verify): orderId={}, paymentId={}, purpose={}", updated.id, req.razorpayPaymentId, updated.purpose)

        if (order.purpose == "WALLET_TOPUP") {
            val credited = walletCreditPort.creditWalletTopup(
                userId = updated.userId,
                walletType = "NBFC",
                amountPaise = updated.amountPaise,
                idempotencyKey = updated.idempotencyKey,
                cashfreeOrderId = req.razorpayOrderId
            )
            if (!credited) {
                log.error("WALLET_TOPUP client-verify: credit failed for orderId={}, userId={}", updated.id, updated.userId)
            }
        }

        publishPaymentCapturedEvent(updated)

        return Result.success(toResponse(updated))
    }

    // ── Razorpay Webhook Handler (Idempotent) ── -- UNCHANGED
    suspend fun handleWebhook(rawPayload: String, signature: String): Boolean {
        if (!verifyHmacSignature(rawPayload, signature, webhookSecret)) {
            log.warn("Razorpay webhook signature verification failed")
            return false
        }

        return try {
            val parsed = objectMapper.readValue<Map<String, Any>>(rawPayload)
            val event = parsed["event"] as? String ?: return true

            when (event) {
                "payment.captured" -> handleWebhookCaptured(parsed, rawPayload)
                "payment.failed"   -> handleWebhookFailed(parsed)
                else -> {
                    log.info("Unhandled Razorpay webhook event: {}", event)
                    true
                }
            }
        } catch (e: Exception) {
            log.error("Razorpay webhook parse error", e)
            false
        }
    }

    private suspend fun handleWebhookCaptured(parsed: Map<String, Any>, rawPayload: String): Boolean {
        val paymentObj = (parsed["payload"] as? Map<*, *>)
            ?.get("payment") as? Map<*, *>
            ?: return true

        val entity = paymentObj["entity"] as? Map<*, *> ?: return true
        val razorpayOrderId = entity["order_id"] as? String ?: return true
        val razorpayPaymentId = entity["id"] as? String ?: return true

        // Recharge creates its own Razorpay order directly (not through
        // PaymentService.createOrder), so it lives in recharge_orders, not
        // payment_orders. Check there first -- if RechargeService recognizes
        // the order AND it's a MOBILE order (its own serviceType guard),
        // it owns completion and we're done.
        if (rechargeService.handleWebhookCaptured(razorpayOrderId, razorpayPaymentId)) {
            return true
        }

        // ← NEW: same recharge_orders table, but a DTH order --
        // RechargeService.handleWebhookCaptured() above already returned
        // false for it (serviceType != "MOBILE" guard). Try the DTH
        // service before falling through to the generic payment_orders
        // path below (which would otherwise log "order not found" for a
        // recharge_orders-only order and never actually deliver the DTH
        // recharge).
        if (dthRechargeService.handleWebhookCaptured(razorpayOrderId, razorpayPaymentId)) {
            return true
        }

        val order = paymentRepo.findByRazorpayOrderId(razorpayOrderId) ?: run {
            log.warn("Razorpay webhook: order not found for razorpayOrderId={}", razorpayOrderId)
            return true  // idempotent — naya order nahi banate webhook se
        }

        // Idempotency — already captured toh no-op
        if (order.status == "CAPTURED") {
            log.info("Razorpay webhook: payment already captured, skipping orderId={}", order.id)
            return true
        }

        val updated = paymentRepo.updateWebhookCaptured(
            id = order.id!!,
            razorpayPaymentId = razorpayPaymentId,
            status = "CAPTURED",
            webhookEvent = "payment.captured",
            webhookPayload = rawPayload
        )

        log.info("Razorpay webhook: payment captured orderId={}, paymentId={}, purpose={}", updated.id, razorpayPaymentId, order.purpose)

        if (order.purpose == "WALLET_TOPUP") {
            val credited = walletCreditPort.creditWalletTopup(
                userId = updated.userId,
                walletType = "NBFC",
                amountPaise = updated.amountPaise,
                idempotencyKey = updated.idempotencyKey,
                cashfreeOrderId = razorpayOrderId
            )
            if (!credited) {
                log.error("WALLET_TOPUP webhook: credit failed for orderId={}, userId={}", updated.id, updated.userId)
            }
        }

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

        log.info("Razorpay webhook: payment failed orderId={}", order.id)
        return true
    }

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
            log.error("Failed to publish payment-captured event for orderId={}: {}", order.id, e.message)
        }
    }

    private fun verifyHmacSignature(payload: String, expectedSignature: String, secret: String): Boolean {
        if (secret.isBlank()) {
            log.error("HMAC secret not configured -- rejecting signature verification")
            return false
        }

        return try {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(secret.toByteArray(), "HmacSHA256"))
            val computedHex = mac.doFinal(payload.toByteArray())
                .joinToString("") { "%02x".format(it) }

            val matches = java.security.MessageDigest.isEqual(
                computedHex.lowercase().toByteArray(),
                expectedSignature.lowercase().toByteArray()
            )

            if (!matches) {
                log.warn(
                    "Razorpay webhook signature mismatch: secretLength={}, payloadLength={}",
                    secret.length, payload.length
                )
            }
            matches
        } catch (e: Exception) {
            log.error("HMAC verification error", e)
            false
        }
    }

    private fun toResponse(entity: PaymentOrderEntity) = PaymentOrderResponse(
        orderId = entity.id!!,
        razorpayOrderId = entity.razorpayOrderId,
        amount = java.math.BigDecimal(entity.amountPaise)
            .divide(java.math.BigDecimal(100), 2, java.math.RoundingMode.HALF_EVEN),
        status = entity.status,
        keyId = razorpayKeyId
    )
}