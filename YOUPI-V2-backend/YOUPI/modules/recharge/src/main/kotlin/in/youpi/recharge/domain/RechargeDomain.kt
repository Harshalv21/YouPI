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
    // Needed to compute expiry_date once the recharge succeeds -- without
    // this the backend has no idea how long the plan the user picked is
    // valid for. Comes from PlanResponse.validity (already fetched and
    // shown to the user before they confirm), just wasn't threaded through
    // to order creation until now.
    val planValidityDays: Int,
    val paymentMode: PaymentMode,
    val idempotencyKey: String
)

enum class PaymentMode {
    FULL, EMI_3, EMI_6, EMI_12, SMART_SAVER_WALLET
}

/**
 * Response from GET /v1/recharge/operator -- powers the slot-machine
 * detection UI. operator/circle are already normalized to the same
 * uppercase format used in operatorCodeMap/circleCodeMap (e.g. "JIO",
 * "UP EAST"), so Flutter can use them directly for both display and the
 * subsequent plan-fetch call without any further transformation.
 */
data class OperatorDetectionResponse(
    val operator: String,
    val circle: String
)

class OperatorDetectionException(detail: String) : RechargeException(
    "OPERATOR_DETECTION_FAILED", detail, 502
)

/**
 * The user's current active recharge, if any -- powers the home screen's
 * "Active Recharge" card (status + end date instead of a static
 * placeholder). Null fields mean "no active recharge right now," not an
 * error -- the endpoint returns 200 with data=null in that case, same
 * convention as other nullable-result endpoints in this codebase.
 */
data class ActiveRechargeResponse(
    val orderId: UUID,
    val mobileNumber: String,
    val operator: String,
    val planAmount: BigDecimal,
    val expiryDate: java.time.LocalDate,
    val daysRemaining: Long
)

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
    val paymentSessionId: String? = null,   // NEW -- Cashfree checkout needs
    // this (not orderId) to open the
    // hosted payment page. Null when
    // gateway is Razorpay.
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