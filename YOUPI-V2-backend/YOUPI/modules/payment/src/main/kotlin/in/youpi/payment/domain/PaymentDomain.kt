package `in`.youpi.payment.domain

import `in`.youpi.core.BaseException
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Positive
import java.math.BigDecimal
import java.util.UUID

// ── Request/Response DTOs ──
// NOTE: enforced via awaitValidatedBody<T>() in the router, not automatically
// (functional coRouter handlers -- see shared/core RequestValidation.kt).

data class CreatePaymentOrderRequest(
    @field:Positive(message = "amount must be positive")
    val amount: BigDecimal,
    val purpose: PaymentPurpose,
    val referenceId: UUID? = null,
    @field:NotBlank(message = "idempotencyKey is required")
    val idempotencyKey: String
)

enum class PaymentPurpose {
    RECHARGE, SMART_DEPOSIT, FD_OPEN, LOAN_EMI, GOLD_BUY, WALLET_TOPUP
}

data class PaymentOrderResponse(
    val orderId: UUID,
    val razorpayOrderId: String,
    val amount: BigDecimal,
    val currency: String = "INR",
    val status: String,
    val keyId: String
)

data class RazorpayWebhookPayload(
    val event: String,
    val payload: Map<String, Any>
)

data class VerifyPaymentRequest(
    @field:NotBlank(message = "razorpayPaymentId is required")
    val razorpayPaymentId: String,
    @field:NotBlank(message = "razorpayOrderId is required")
    val razorpayOrderId: String,
    @field:NotBlank(message = "razorpaySignature is required")
    val razorpaySignature: String
)

// ── Sealed Exceptions ──

sealed class PaymentException(
    code: String,
    message: String,
    httpStatus: Int = 400
) : BaseException(code, message) {
    override val httpStatus: Int = httpStatus
}

class PaymentOrderNotFoundException(val orderId: String) : PaymentException(
    "PAYMENT_ORDER_NOT_FOUND", "Payment order not found: $orderId", 404
)
class PaymentSignatureInvalidException : PaymentException(
    "PAYMENT_SIGNATURE_INVALID", "Razorpay signature verification failed."
)
class PaymentAlreadyCaptured(val orderId: UUID) : PaymentException(
    "PAYMENT_ALREADY_CAPTURED", "Payment already captured for order: $orderId", 200
)
class WebhookSignatureInvalidException : PaymentException(
    "WEBHOOK_SIGNATURE_INVALID", "Webhook HMAC signature verification failed.", 401
)
class PaymentOrderCreationFailedException(detail: String) : PaymentException(
    "PAYMENT_ORDER_CREATION_FAILED", "Could not create payment order: $detail", 502
)