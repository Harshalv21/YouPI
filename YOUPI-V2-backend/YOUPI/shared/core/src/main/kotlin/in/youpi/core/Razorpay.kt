package `in`.youpi.core.razorpay

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.MediaType
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient
import org.springframework.web.reactive.function.client.awaitBody
import java.util.Base64


@JsonIgnoreProperties(ignoreUnknown = true)
data class RazorpayOrderResult(
    val id: String,
    val amount: Long,
    val currency: String,
    val receipt: String?,
    // Razorpay order status values: "created", "attempted", "paid" -- NOT
    // the same vocabulary as Cashfree's ("ACTIVE", "PAID", "EXPIRED",
    // "TERMINATED"). Callers (e.g. WalletService's sweeper) must branch on
    // Razorpay's own values, not Cashfree's -- see fetchOrder() below.
    val status: String
)

class RazorpayOrderCreationException(message: String) : RuntimeException(message)

@JsonIgnoreProperties(ignoreUnknown = true)
data class RazorpayRefundResult(
    val id: String,
    val amount: Long,
    val status: String,
    @com.fasterxml.jackson.annotation.JsonProperty("payment_id")
    val paymentId: String? = null
)

class RazorpayRefundException(message: String) : RuntimeException(message)

/**
 * Thin client for Razorpay's Orders API.
 *
 * Configure via youpi.razorpay.key-id / youpi.razorpay.key-secret.
 */
@Component
class RazorpayClient(
    private val webClient: WebClient,
    @Value("\${youpi.razorpay.key-id:}") private val keyId: String,
    @Value("\${youpi.razorpay.key-secret:}") private val keySecret: String
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private val authHeader: String by lazy {
        "Basic " + Base64.getEncoder().encodeToString("$keyId:$keySecret".toByteArray())
    }

    /**
     * Creates a real order on Razorpay.
     *
     * @param amountPaise amount in the smallest currency unit (paise for INR
     *   -- e.g. ₹22 = 2200). Razorpay's API requires this, not rupees.
     * @param receipt your own reference for this order (idempotency key works
     *   well here) -- shows up in the Razorpay dashboard for reconciliation.
     * @throws RazorpayOrderCreationException if keys aren't configured or the
     *   API call fails. Callers should treat this as a hard failure -- never
     *   fall back to a fake ID, since that silently breaks payment entirely.
     */
    suspend fun createOrder(
        amountPaise: Long,
        receipt: String,
        notes: Map<String, String> = emptyMap()
    ): RazorpayOrderResult {
        if (keyId.isBlank() || keySecret.isBlank()) {
            throw RazorpayOrderCreationException(
                "Razorpay API keys not configured (youpi.razorpay.key-id / key-secret)"
            )
        }

        return try {
            webClient.post()
                .uri("https://api.razorpay.com/v1/orders")
                .header("Authorization", authHeader)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(
                    mapOf(
                        "amount" to amountPaise,
                        "currency" to "INR",
                        "receipt" to receipt,
                        "payment_capture" to 1,
                        "notes" to notes
                    )
                )
                .retrieve()
                .awaitBody<RazorpayOrderResult>()
        } catch (e: Exception) {
            log.error("Razorpay order creation failed for receipt={}: {}", receipt, e.message)
            throw RazorpayOrderCreationException("Razorpay order creation failed: ${e.message}")
        }
    }

    /**
     * Fetches current order status directly from Razorpay -- used by
     * WalletService.sweepPendingTopups() as a missed-webhook safety net,
     * same role Cashfree's getOrderStatus() played before this revert.
     *
     * IMPORTANT: Razorpay's order.status vocabulary is "created" /
     * "attempted" / "paid" -- there is no direct equivalent of Cashfree's
     * "EXPIRED"/"TERMINATED" terminal-failure states here. A Razorpay order
     * that never gets paid just stays "created"/"attempted" indefinitely;
     * callers should rely on their own max-age cutoff (as
     * sweepPendingTopups() already does) to eventually stop polling and
     * give up, rather than expecting a distinct "expired" status back.
     *
     * This does NOT return a payment id even when status="paid" -- Razorpay
     * doesn't include one on the order resource itself. If you need the
     * payment_id (e.g. to issue a refund), call fetchOrderPayments()
     * separately.
     */
    suspend fun fetchOrder(orderId: String): RazorpayOrderResult {
        if (keyId.isBlank() || keySecret.isBlank()) {
            throw RazorpayOrderCreationException(
                "Razorpay API keys not configured (youpi.razorpay.key-id / key-secret)"
            )
        }

        return try {
            webClient.get()
                .uri("https://api.razorpay.com/v1/orders/$orderId")
                .header("Authorization", authHeader)
                .retrieve()
                .awaitBody<RazorpayOrderResult>()
        } catch (e: Exception) {
            log.error("Razorpay order fetch failed for orderId={}: {}", orderId, e.message)
            throw RazorpayOrderCreationException("Razorpay order fetch failed: ${e.message}")
        }
    }

    /**
     * Fetches the first payment id associated with a paid order -- needed
     * because fetchOrder() alone doesn't return one. Only meaningful to
     * call once fetchOrder().status == "paid". Returns null if the order
     * has no payments yet (shouldn't happen if status is "paid", but
     * defensive rather than throwing).
     */
    @Suppress("UNCHECKED_CAST")
    suspend fun fetchFirstPaymentId(orderId: String): String? {
        if (keyId.isBlank() || keySecret.isBlank()) {
            throw RazorpayOrderCreationException(
                "Razorpay API keys not configured (youpi.razorpay.key-id / key-secret)"
            )
        }

        return try {
            val response = webClient.get()
                .uri("https://api.razorpay.com/v1/orders/$orderId/payments")
                .header("Authorization", authHeader)
                .retrieve()
                .awaitBody<Map<String, Any>>()

            val items = response["items"] as? List<Map<String, Any>>
            items?.firstOrNull()?.get("id") as? String
        } catch (e: Exception) {
            log.error("Razorpay order-payments fetch failed for orderId={}: {}", orderId, e.message)
            null
        }
    }

    /**
     * Refunds a captured payment. Used when payment succeeded but the
     * downstream service (e.g. A1Topup recharge delivery) failed -- the
     * customer must get their money back automatically, not just have the
     * order silently marked RECHARGE_FAILED with cash sitting uncollected.
     *
     * @param paymentId the razorpay_payment_id of the CAPTURED payment
     *   (not the order id -- refunds are issued against payments).
     * @param amountPaise optional partial-refund amount; omit for a full
     *   refund of whatever was captured.
     * @param notes free-form reference info, shows up in Razorpay dashboard
     *   (e.g. the internal recharge order id, so ops can reconcile).
     * @throws RazorpayRefundException if keys aren't configured or the API
     *   call fails. Callers MUST NOT swallow this silently -- a failed
     *   refund call means the customer is still owed money and needs a
     *   manual ops follow-up, not just a log line.
     */
    suspend fun refund(
        paymentId: String,
        amountPaise: Long? = null,
        notes: Map<String, String> = emptyMap()
    ): RazorpayRefundResult {
        if (keyId.isBlank() || keySecret.isBlank()) {
            throw RazorpayRefundException(
                "Razorpay API keys not configured (youpi.razorpay.key-id / key-secret)"
            )
        }

        val body = buildMap<String, Any> {
            amountPaise?.let { put("amount", it) }
            put("notes", notes)
        }

        return try {
            webClient.post()
                .uri("https://api.razorpay.com/v1/payments/$paymentId/refund")
                .header("Authorization", authHeader)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(body)
                .retrieve()
                .awaitBody<RazorpayRefundResult>()
        } catch (e: Exception) {
            log.error("Razorpay refund failed for paymentId={}: {}", paymentId, e.message)
            throw RazorpayRefundException("Razorpay refund failed: ${e.message}")
        }
    }
}