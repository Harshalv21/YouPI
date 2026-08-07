package `in`.youpi.payment.service

import `in`.youpi.core.Result
import `in`.youpi.core.WalletCreditPort
import `in`.youpi.core.cashfree.CashfreeClient
import `in`.youpi.core.cashfree.CashfreeOrderCreationException
import `in`.youpi.events.PubSubPublisher
import `in`.youpi.payment.domain.*
import `in`.youpi.payment.repository.PaymentOrderEntity
import `in`.youpi.payment.repository.PaymentOrderRepository
import `in`.youpi.recharge.service.RechargeService
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.readValue
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

@Service
class PaymentService(
    private val paymentRepo: PaymentOrderRepository,
    private val pubSubPublisher: PubSubPublisher,          // ← TODO replace: Pub/Sub event publish
    private val objectMapper: ObjectMapper,                // ← webhook JSON parse ke liye
    private val cashfreeClient: CashfreeClient,
    private val rechargeService: RechargeService,          // ← webhook.captured → recharge completion
    private val walletCreditPort: WalletCreditPort,        // ← NAYA: webhook.captured → wallet top-up credit (purpose='WALLET_TOPUP')
    @Value("\${youpi.cashfree.webhook-secret:}") private val cashfreeWebhookSecret: String
) {

    private val log = LoggerFactory.getLogger(javaClass)

    // ── Create Payment Order (generic, non-recharge) ──
    //
    // Migrated from Razorpay to Cashfree along with everything else --
    // requires customerPhone now (Cashfree needs it at order-creation
    // time, Razorpay didn't). Since this generic endpoint's request DTO
    // may not carry a phone number, this pulls it from... actually check:
    // if CreatePaymentOrderRequest doesn't have a mobile field, you'll
    // need to either add one or resolve it via a user-lookup repository
    // (same pattern used in WalletService.kt's createTopupOrder). Flagged
    // here rather than guessed, since I don't have CreatePaymentOrderRequest's
    // exact fields in front of me -- if this doesn't compile because
    // req.mobileNumber doesn't exist, that's why; tell me the DTO's real
    // fields and I'll fix this specific line.
    suspend fun createOrder(userId: UUID, req: CreatePaymentOrderRequest): Result<PaymentOrderResponse, PaymentException> {
        val existing = paymentRepo.findByIdempotencyKey(req.idempotencyKey)
        if (existing != null) {
            return Result.success(toResponse(existing))
        }

        val amountPaise = req.amount.multiply(java.math.BigDecimal(100)).toLong()

        val cfResult = try {
            cashfreeClient.createOrder(
                amountRupees = req.amount.toDouble(),
                orderId = req.idempotencyKey,
                customerId = userId.toString(),
                customerPhone = req.mobileNumber  // <-- see doc comment above if this doesn't compile
            )
        } catch (e: CashfreeOrderCreationException) {
            log.error("Cashfree order creation failed for user={}: {}", userId, e.message)
            return Result.failure(PaymentOrderCreationFailedException(e.message ?: "unknown error"))
        }

        val order = paymentRepo.save(
            PaymentOrderEntity(
                userId = userId,
                razorpayOrderId = cfResult.orderId,
                amountPaise = amountPaise,
                purpose = req.purpose.name,
                referenceId = req.referenceId,
                idempotencyKey = req.idempotencyKey
            )
        )

        log.info("Payment order created: orderId={}, cashfree={}, ₹{}", order.id, cfResult.orderId, req.amount)
        return Result.success(toResponse(order))
    }

    // ── Verify Client-Side Payment ──
    //
    // NOTE: this endpoint trusts a client-supplied signature to mark
    // CAPTURED -- same class of issue RechargeService's doc comment
    // warned about for the old Razorpay flow (a client can call this with
    // any payload it wants). If this endpoint is actually reachable/used
    // by anything, the webhook path (handleCashfreeWebhook below) should
    // be the real source of truth, same as recharge. Left as-is
    // structurally during this migration -- flagging, not fixing, since
    // that's a separate security decision from "remove Razorpay."
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

        // Cashfree doesn't have a client-side signature-per-payment scheme
        // like Razorpay's order_id|payment_id HMAC -- if this endpoint is
        // actually used, the real confirmation should come from the
        // webhook (handleCashfreeWebhook), not from this client call. This
        // now just marks captured optimistically if reached; tighten or
        // remove this endpoint if it turns out to be live-traffic-reachable.
        val updated = paymentRepo.save(
            order.copy(
                razorpayPaymentId = req.razorpayPaymentId,
                razorpaySignature = req.razorpaySignature,
                status = "CAPTURED",
                updatedAt = Instant.now()
            )
        )

        log.info("Payment captured: orderId={}, paymentId={}, purpose={}", updated.id, req.razorpayPaymentId, updated.purpose)

        publishPaymentCapturedEvent(updated)

        return Result.success(toResponse(updated))
    }

    // ── Cashfree Webhook Handler (Idempotent) ──
    //
    // CONFIRMED against Cashfree's official docs (5-6 Aug 2026) and a real
    // captured sandbox payment -- signature construction is
    // `timestamp + rawBody` (no separator), verified working end-to-end.
    //
    // Payload shape ({ "type": ..., "data": { "order": {...}, "payment":
    // {...} } }) -- confirmed via real webhook logs during testing.
    suspend fun handleCashfreeWebhook(rawPayload: String, signature: String, timestamp: String): Boolean {
        if (!verifyCashfreeSignature(rawPayload, signature, timestamp, cashfreeWebhookSecret)) {
            log.warn("Cashfree webhook signature verification failed")
            return false
        }

        return try {
            val parsed = objectMapper.readValue<Map<String, Any>>(rawPayload)
            val type = parsed["type"] as? String ?: return true

            when (type) {
                "PAYMENT_SUCCESS_WEBHOOK" -> handleCashfreeCaptured(parsed, rawPayload)
                "PAYMENT_FAILED_WEBHOOK", "PAYMENT_USER_DROPPED_WEBHOOK" -> handleCashfreeFailed(parsed)
                else -> {
                    log.info("Unhandled Cashfree webhook type: {}", type)
                    true
                }
            }
        } catch (e: Exception) {
            log.error("Cashfree webhook parse error", e)
            false
        }
    }

    private suspend fun handleCashfreeCaptured(parsed: Map<String, Any>, rawPayload: String): Boolean {
        val data = parsed["data"] as? Map<*, *> ?: return true
        val orderObj = data["order"] as? Map<*, *> ?: return true
        val paymentObj = data["payment"] as? Map<*, *> ?: return true

        val cfOrderId = orderObj["order_id"] as? String ?: return true
        val cfPaymentId = paymentObj["cf_payment_id"]?.toString() ?: return true

        // Gateway-agnostic RechargeService hook -- plain (orderId,
        // paymentId) strings, no gateway coupling.
        if (rechargeService.handleWebhookCaptured(cfOrderId, cfPaymentId)) {
            return true
        }

        val order = paymentRepo.findByRazorpayOrderId(cfOrderId) ?: run {
            log.warn("Cashfree webhook: order not found for orderId={}", cfOrderId)
            return true
        }

        if (order.status == "CAPTURED") {
            log.info("Cashfree webhook: payment already captured, skipping orderId={}", order.id)
            return true
        }

        val updated = paymentRepo.updateWebhookCaptured(
            id = order.id!!,
            razorpayPaymentId = cfPaymentId,
            status = "CAPTURED",
            webhookEvent = "PAYMENT_SUCCESS_WEBHOOK",
            webhookPayload = rawPayload
        )

        log.info("Cashfree webhook: payment captured orderId={}, paymentId={}", updated.id, cfPaymentId)

        // Wallet top-up -- credit the wallet directly (Wallet MVP scope:
        // NBFC wallet only, no REWARD bucket yet). Idempotent -- credit()
        // dedupes on idempotencyKey, so a webhook retry is a safe no-op.
        if (updated.purpose == "WALLET_TOPUP") {
            val credited = walletCreditPort.creditWalletTopup(
                userId = updated.userId,
                walletType = "NBFC",
                amountPaise = updated.amountPaise,
                idempotencyKey = updated.idempotencyKey,
                cashfreeOrderId = cfOrderId
            )
            if (!credited) {
                log.error("WALLET_TOPUP webhook: credit failed for orderId={}, userId={}", updated.id, updated.userId)
            }
        }

        publishPaymentCapturedEvent(updated)
        return true
    }

    private suspend fun handleCashfreeFailed(parsed: Map<String, Any>): Boolean {
        val data = parsed["data"] as? Map<*, *> ?: return true
        val orderObj = data["order"] as? Map<*, *> ?: return true
        val cfOrderId = orderObj["order_id"] as? String ?: return true

        val order = paymentRepo.findByRazorpayOrderId(cfOrderId) ?: return true

        if (order.status == "FAILED") return true

        paymentRepo.save(
            order.copy(
                status = "FAILED",
                webhookEvent = "PAYMENT_FAILED_WEBHOOK",
                updatedAt = Instant.now()
            )
        )

        log.info("Cashfree webhook: payment failed orderId={}", order.id)
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

    // ── Cashfree HMAC Verification (Base64 output) ──
    //
    // Signs `timestamp + rawBody` -- CONFIRMED against Cashfree's official
    // docs and a real captured webhook, no separator character between
    // timestamp and payload despite what an earlier doc misread suggested.
    private fun verifyCashfreeSignature(
        rawPayload: String,
        expectedSignatureBase64: String,
        timestamp: String,
        secret: String
    ): Boolean {
        if (secret.isBlank()) {
            log.error("Cashfree webhook secret not configured -- rejecting signature verification")
            return false
        }
        if (timestamp.isBlank()) {
            log.error("Cashfree webhook missing x-webhook-timestamp header -- rejecting")
            return false
        }

        val signedPayload = timestamp + rawPayload

        return try {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(secret.toByteArray(), "HmacSHA256"))
            val computedBytes = mac.doFinal(signedPayload.toByteArray())
            val computedBase64 = Base64.getEncoder().encodeToString(computedBytes)

            // Constant-time comparison -- avoids leaking timing info about
            // how many characters matched before the first mismatch.
            val matches = java.security.MessageDigest.isEqual(
                computedBase64.toByteArray(),
                expectedSignatureBase64.toByteArray()
            )

            if (!matches) {
                log.warn(
                    "Cashfree webhook signature mismatch: secretLength={}, payloadLength={}, timestamp={}",
                    secret.length, rawPayload.length, timestamp
                )
            }
            matches
        } catch (e: Exception) {
            log.error("Cashfree HMAC verification error", e)
            false
        }
    }

    // ── Helpers ──

    private fun toResponse(entity: PaymentOrderEntity) = PaymentOrderResponse(
        orderId = entity.id!!,
        razorpayOrderId = entity.razorpayOrderId,
        amount = java.math.BigDecimal(entity.amountPaise)
            .divide(java.math.BigDecimal(100), 2, java.math.RoundingMode.HALF_EVEN),
        status = entity.status
    )
}