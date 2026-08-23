package `in`.youpi.recharge.domain

import `in`.youpi.core.BaseException
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Positive
import java.math.BigDecimal
import java.util.UUID

// ── Request DTOs ──
// NOTE: enforced via awaitValidatedBody<T>() in the router, not automatically
// (functional coRouter handlers -- see shared/core RequestValidation.kt).
// planAmount/planValidityDays below are still re-resolved server-side from
// the plan catalog regardless of what passes validation here (see
// RechargeService.resolveAuthoritativePlan()) -- these annotations reject
// obviously-malformed junk early, they are not the source of trust for price.

data class FetchPlansRequest(
    val operator: String,
    val circle: String
)

data class CreateRechargeRequest(
    @field:Pattern(regexp = "^[6-9]\\d{9}$", message = "Invalid mobile number")
    val mobileNumber: String,
    @field:NotBlank(message = "operator is required")
    val operator: String,
    val circle: String? = null,
    @field:NotBlank(message = "planId is required")
    val planId: String,
    @field:Positive(message = "planAmount must be positive")
    val planAmount: BigDecimal,
    // Needed to compute expiry_date once the recharge succeeds -- without
    // this the backend has no idea how long the plan the user picked is
    // valid for. Comes from PlanResponse.validity (already fetched and
    // shown to the user before they confirm), just wasn't threaded through
    // to order creation until now.
    @field:Positive(message = "planValidityDays must be positive")
    val planValidityDays: Int,
    val paymentMode: PaymentMode,
    @field:NotBlank(message = "idempotencyKey is required")
    val idempotencyKey: String,
    // ← NEW: only required when paymentMode == SPLIT. The user-consented
    // wallet-portion amount (rest goes via Razorpay). Still re-validated
    // server-side against live wallet balance in
    // RechargeService.createSplitPaymentOrder() -- never trust this alone.
    val walletAmount: BigDecimal? = null
)

// ← CHANGED: SPLIT added. FULL = existing gateway-only mode (Razorpay for
// the entire plan amount). WALLET = existing full-wallet mode. SPLIT = NEW,
// part wallet + part Razorpay.
enum class PaymentMode {
    FULL, EMI_3, EMI_6, EMI_12, SMART_SAVER_WALLET, WALLET, SPLIT
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
    @field:NotBlank(message = "razorpayPaymentId is required")
    val razorpayPaymentId: String,
    @field:NotBlank(message = "razorpayOrderId is required")
    val razorpayOrderId: String,
    @field:NotBlank(message = "razorpaySignature is required")
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
    val paymentSessionId: String? = null,   // legacy Cashfree field, ab hamesha null
    val razorpayKeyId: String? = null,    // Razorpay checkout SDK ke liye chahiye
    // this (not orderId) to open the
    // hosted payment page. Null when
    // gateway is Razorpay.
    // For SPLIT orders: this is the GATEWAY-CHARGE amount (what Razorpay
    // checkout should open for), NOT the full plan price. Full plan price
    // isn't repeated here -- client already has it from the plan the user
    // picked. See walletAmount/gatewayAmount below for the breakdown.
    val amount: BigDecimal,
    val status: String,
    val paymentMode: String,
    // ← NEW: populated only for SPLIT orders. Lets the UI show an exact
    // "₹149 from Wallet + ₹200 via UPI" breakdown without re-deriving it,
    // and lets recharge_viewmodel.dart know unambiguously what amount to
    // pass into the Razorpay checkout SDK (gatewayAmount, not `amount`
    // being confused with the full plan price).
    val walletAmount: BigDecimal? = null,
    val gatewayAmount: BigDecimal? = null
)

data class RechargeStatusResponse(
    val orderId: UUID,
    val status: String,
    val mobileNumber: String,
    val operator: String,
    val planAmount: BigDecimal,
    val a1TopupStatus: String?,
    val goldTxnId: UUID?,
    val createdAt: java.time.Instant
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
    httpStatus: Int = 400,
    details: Map<String, Any>? = null
) : BaseException(code = code, message = message, details = details) {
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
class RechargePlanPriceMismatchException : RechargeException(
    "PLAN_PRICE_MISMATCH", "Plan price changed. Please refresh plans and retry.", 409
)
class RechargeAlreadyConfirmedException(val orderId: UUID) : RechargeException(
    "RECHARGE_ALREADY_CONFIRMED", "Recharge order $orderId is already confirmed.", 409
)

// ← CHANGED: available/required optional params add kiye, taaki client ko
// exact wallet balance + shortfall mile "Add Money" CTA ke liye
class WalletPaymentRejectedException(
    reason: String,
    available: BigDecimal? = null,
    required: BigDecimal? = null
) : RechargeException(
    code = "WALLET_PAYMENT_REJECTED",
    message = reason,
    httpStatus = 402,
    details = if (available != null && required != null) mapOf(
        "walletBalance" to available,
        "requiredAmount" to required,
        "shortfall" to (required - available)
    ) else null
)