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

/**
 * mPlan's own DTH operator_code values -- CONFIRMED from mPlan's
 * "Operator Codes" docs page (Sep 2026). Deliberately a SEPARATE map from
 * A1TopupClient's CONFIRMED_DTH_OPERATOR_CODES -- mPlan and A1Topup are
 * different vendors with their own independent operator-code schemes, even
 * though both happen to key off the same SUPPORTED_DTH_OPERATORS names
 * used elsewhere in this file. Only used by RechargeService's
 * fetchDthCustomerInfoByVc()/fetchDthCustomerInfoByMobile() -- NOT by
 * anything A1Topup-related.
 */
val MPLAN_DTH_OPERATOR_CODES = mapOf(
    "DISH TV" to 6,
    "TATA PLAY" to 7,
    "VIDEOCON D2H" to 11,
    "SUN DIRECT" to 12,
    "AIRTEL DIGITAL TV" to 24
)

/**
 * Response shape for mPlan's DTH Customer Info APIs -- both the
 * vc_number-keyed (/dth_info) and mobile_number-keyed (/dth_info_mobile)
 * variants, normalized into one model since RechargeService parses both
 * the same way (see fetchDthCustomerInfo() private helper). Not every
 * field is present on both variants in practice (e.g. the mobile-number
 * variant's example response had no `status`/`Balance`/`NextRechargeDate`/
 * `planname`) -- all fields besides customerName/monthlyRecharge are
 * therefore nullable rather than assumed always-present.
 *
 * `isActive` is derived, not a raw mPlan field: true only when mPlan
 * returns status == "ACTIVE" (case-insensitive). Since the mobile-number
 * variant doesn't return a status field at all, isActive will be false for
 * that variant even for a genuinely active subscriber -- callers using
 * that variant should treat isActive as "unknown" rather than "inactive"
 * unless/until mPlan confirms that variant never returns status.
 */
data class DthCustomerInfoResponse(
    val custId: String?,
    val customerName: String?,
    val monthlyRecharge: BigDecimal?,
    val balance: BigDecimal?,
    val nextRechargeDate: String?,
    val status: String?,
    val planName: String?,
    val isActive: Boolean
)