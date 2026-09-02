package `in`.youpi.recharge.domain.dth

import `in`.youpi.recharge.domain.PaymentMode
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Positive
import java.math.BigDecimal

// ── DTH-specific DTOs ──
// Kept in their own file/package (domain/dth/) rather than added to the
// shared recharge/domain.kt, to isolate DTH from mobile recharge as much
// as possible. Reuses PaymentMode from the shared domain package, and
// reuses RechargeOrderResponse/RechargeStatusResponse/RechargeException +
// subclasses from `in.youpi.recharge.domain` as response/error types --
// see DthRechargeService.kt. Only the DTH-specific REQUEST shape is new.

/**
 * No plan catalog exists for DTH via A1Topup -- their docs only expose a
 * single combined Mobile/DTH/Postpaid/Utility recharge API, with no
 * DTH plan-listing endpoint. So unlike mobile recharge's
 * CreateRechargeRequest (which carries a planId verified server-side
 * against a fetched catalog), the user enters `amount` directly here --
 * same UX as a utility-bill payment. `amount` is the source of truth,
 * bounded only by DthRechargeService.MIN_DELIVERABLE_AMOUNT.
 */
data class CreateDthRechargeRequest(
    // DTH subscriber/VC (Viewer Card) numbers are operator-issued and not
    // a fixed format across operators (mostly numeric, occasionally
    // alphanumeric) -- kept permissive rather than guessing a stricter
    // pattern that might reject a legitimate VC number.
    @field:Pattern(regexp = "^[A-Za-z0-9]{6,15}$", message = "Invalid subscriber/VC number")
    val subscriberNumber: String,
    @field:NotBlank(message = "operator is required")
    val operator: String,
    @field:Positive(message = "amount must be positive")
    val amount: BigDecimal,
    val paymentMode: PaymentMode,
    @field:NotBlank(message = "idempotencyKey is required")
    val idempotencyKey: String
    // NOTE: no walletAmount/SPLIT field -- SPLIT payment mode is not
    // wired up for DTH (see DthRechargeService.createOrder()).
)

/**
 * Static list of A1Topup-confirmed DTH operators, straight from their
 * Recharge API docs' Operator Code table. Not fetched from any API --
 * A1Topup doesn't expose a "list DTH operators" endpoint, this is simply
 * the fixed set they document. Powers GET /v1/recharge/dth/operators.
 */
data class DthOperatorInfo(
    val name: String,
    val displayName: String
)

val SUPPORTED_DTH_OPERATORS = listOf(
    DthOperatorInfo("AIRTEL DIGITAL TV", "Airtel Digital TV"),
    DthOperatorInfo("SUN DIRECT", "Sun Direct"),
    DthOperatorInfo("TATA PLAY", "Tata Play (Tata Sky)"),
    DthOperatorInfo("VIDEOCON D2H", "Videocon d2h"),
    DthOperatorInfo("DISH TV", "Dish TV")
)