package `in`.youpi.payment.domain

import `in`.youpi.core.BaseException
import java.math.BigDecimal
import java.util.UUID

// ── Request/Response DTOs ──

data class CreatePaymentOrderRequest(
    val amount: BigDecimal,
    val purpose: PaymentPurpose,
    val referenceId: UUID? = null,
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
    val razorpayPaymentId: String,
    val razorpayOrderId: String,
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
