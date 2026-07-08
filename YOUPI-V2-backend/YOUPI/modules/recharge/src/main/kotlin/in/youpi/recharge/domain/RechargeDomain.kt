package `in`.youpi.recharge.domain

import `in`.youpi.core.BaseException
import java.math.BigDecimal
import java.util.UUID

// ── Request DTOs ──

data class FetchPlansRequest(
    val operator: String,
    val circle: String
)

data class CreateRechargeRequest(
    val mobileNumber: String,
    val operator: String,
    val circle: String? = null,
    val planId: String,
    val planAmount: BigDecimal,
    val paymentMode: PaymentMode,
    val idempotencyKey: String
)

enum class PaymentMode {
    FULL, EMI_3, EMI_6, EMI_12, SMART_SAVER_WALLET
}

data class ConfirmRechargeRequest(
    val rechargeOrderId: UUID,
    val razorpayPaymentId: String,
    val razorpayOrderId: String,
    val razorpaySignature: String
)

// ── Response DTOs ──

data class PlanResponse(
    val planId: String,
    val operator: String,
    val circle: String,
    val amount: BigDecimal,
    val validity: String,
    val description: String,
    val category: String,
    val data: String? = null,
    val talktime: String? = null,
    val sms: String? = null
)

data class RechargeOrderResponse(
    val orderId: UUID,
    val razorpayOrderId: String?,
    val amount: BigDecimal,
    val status: String,
    val paymentMode: String
)

data class RechargeStatusResponse(
    val orderId: UUID,
    val status: String,
    val mobileNumber: String,
    val operator: String,
    val planAmount: BigDecimal,
    val a1TopupStatus: String?,
    val goldTxnId: UUID?
)

/**
 * Response for the confirm-recharge endpoint.
 * Carries gold auto-invest outcome so the Flutter success screen can
 * show the "gold coin saved" animation, or a soft warning if the
 * auto-invest could not be completed (recharge itself still succeeds).
 */
data class ConfirmRechargeResponse(
    val orderId: UUID,
    val status: String,
    val a1TopupStatus: String?,
    val goldAutoInvest: Boolean,
    val goldTxnId: UUID?,
    val goldInvestAmount: BigDecimal?,
    val goldWarning: String? = null
)

// ── Sealed Exceptions ──

sealed class RechargeException(
    code: String,
    message: String,
    httpStatus: Int = 400
) : BaseException(code, message) {
    override val httpStatus: Int = httpStatus
}

class PlanFetchTimeoutException : RechargeException("PLAN_FETCH_TIMEOUT", "Plan fetch timed out.", 503)
class PlanNotFoundException : RechargeException("PLAN_NOT_FOUND", "Plan not found for given operator/circle.", 404)
class PaymentVerificationException : RechargeException("PAYMENT_VERIFICATION_FAILED", "Payment signature mismatch.")
class InsufficientSmartSaverBalanceException(val available: BigDecimal, val required: BigDecimal) : RechargeException(
    "INSUFFICIENT_CREDIT", "Insufficient Smart Saver credit. Available: $available, Required: $required", 402
)
class RechargeOrderNotFoundException(val orderId: UUID) : RechargeException(
    "RECHARGE_ORDER_NOT_FOUND", "Recharge order $orderId not found.", 404
)
class RechargeDuplicateException(val idempotencyKey: String) : RechargeException(
    "DUPLICATE_RECHARGE", "Recharge already processed for key: $idempotencyKey", 409
)
class RechargeApiException(detail: String) : RechargeException(
    "RECHARGE_API_ERROR", detail, 502
)
class RechargeAlreadyConfirmedException(val orderId: UUID) : RechargeException(
    "RECHARGE_ALREADY_CONFIRMED", "Recharge order $orderId is already confirmed.", 409
)