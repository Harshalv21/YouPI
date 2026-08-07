package `in`.youpi.core.cashfree

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import com.fasterxml.jackson.annotation.JsonProperty
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.MediaType
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient
import org.springframework.web.reactive.function.client.awaitBody

/**
 * order_meta -- passed at order-creation time. notify_url is REQUIRED here
 * (unlike Razorpay, Cashfree has no fixed dashboard webhook as the primary
 * mechanism -- the dashboard "Webhook Endpoint" you configured is only a
 * fallback; the notify_url sent per-order is what actually fires).
 */
data class CashfreeOrderMeta(
    @JsonProperty("return_url") val returnUrl: String? = null,
    @JsonProperty("notify_url") val notifyUrl: String? = null
)

data class CashfreeCustomerDetails(
    @JsonProperty("customer_id") val customerId: String,
    @JsonProperty("customer_phone") val customerPhone: String,
    @JsonProperty("customer_email") val customerEmail: String? = null,
    @JsonProperty("customer_name") val customerName: String? = null
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class CashfreeOrderResult(
    @JsonProperty("cf_order_id") val cfOrderId: String? = null,
    @JsonProperty("order_id") val orderId: String,
    @JsonProperty("order_status") val orderStatus: String? = null,
    @JsonProperty("payment_session_id") val paymentSessionId: String,
    @JsonProperty("order_amount") val orderAmount: Double? = null,
    @JsonProperty("order_currency") val orderCurrency: String? = null
)

class CashfreeOrderCreationException(message: String) : RuntimeException(message)

@JsonIgnoreProperties(ignoreUnknown = true)
data class CashfreeRefundResult(
    @JsonProperty("refund_id") val refundId: String? = null,
    @JsonProperty("cf_refund_id") val cfRefundId: String? = null,
    @JsonProperty("order_id") val orderId: String? = null,
    @JsonProperty("refund_amount") val refundAmount: Double? = null,
    @JsonProperty("refund_status") val refundStatus: String? = null
)

class CashfreeRefundException(message: String) : RuntimeException(message)

/**
 * Thin client for Cashfree's Payment Gateway Orders API (PG API v3,
 * version header "2023-08-01" -- confirmed against the sandbox dashboard
 * on 5 Aug 2026; re-check Cashfree's current docs before going live in
 * case the version has moved on).
 *
 * Mirrors RazorpayClient.kt's shape (same createOrder/refund contract) so
 * RechargeService.kt's call sites only need a client swap, not a rewrite --
 * see youpi.payment.gateway feature flag in the migration plan for the
 * phased-rollout approach.
 *
 * KEY DIFFERENCES FROM RAZORPAY -- do not copy-paste assumptions:
 *  - Auth is two headers (x-client-id / x-client-secret), not Basic auth.
 *  - Amount is in RUPEES here, not paise -- verify against current docs
 *    before wiring call sites; this was flagged as unconfirmed in the
 *    migration doc.
 *  - Order-create returns payment_session_id, which is what the Flutter
 *    Cashfree SDK opens checkout with -- NOT the order_id.
 *  - notify_url must be sent per-order in order_meta; there is no
 *    equivalent of Razorpay's single dashboard-level webhook URL being
 *    the only thing that fires.
 *  - Sandbox and production have different base URLs (not just a mode
 *    toggle on the same host).
 */
@Component
class CashfreeClient(
    private val webClient: WebClient,
    @Value("\${youpi.cashfree.app-id:}") private val appId: String,
    @Value("\${youpi.cashfree.secret-key:}") private val secretKey: String,
    @Value("\${youpi.cashfree.environment:SANDBOX}") private val environment: String,
    @Value("\${youpi.cashfree.api-version:2023-08-01}") private val apiVersion: String,
    @Value("\${youpi.cashfree.notify-url:}") private val defaultNotifyUrl: String
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private val baseUrl: String by lazy {
        if (environment.equals("PRODUCTION", ignoreCase = true)) {
            "https://api.cashfree.com/pg"
        } else {
            "https://sandbox.cashfree.com/pg"
        }
    }

    private fun post(path: String) = webClient.post()
        .uri("$baseUrl$path")
        .header("x-client-id", appId)
        .header("x-client-secret", secretKey)
        .header("x-api-version", apiVersion)
        .contentType(MediaType.APPLICATION_JSON)

    /**
     * Creates a real order on Cashfree.
     *
     * @param amountRupees amount in rupees (e.g. ₹249 = 249.0) -- CONFIRM
     *   against current Cashfree docs before relying on this; the
     *   migration doc flagged amount-unit as unverified.
     * @param orderId your own reference for this order (idempotency key
     *   works well here -- same pattern as Razorpay's `receipt`).
     * @param customerId a stable per-user identifier (e.g. userId UUID as
     *   string) -- Cashfree requires customer_details on every order,
     *   unlike Razorpay which doesn't need it at order-creation time.
     * @param customerPhone required by Cashfree's customer_details block.
     * @param notifyUrl per-order webhook URL; falls back to
     *   youpi.cashfree.notify-url if not supplied.
     * @throws CashfreeOrderCreationException if keys aren't configured or
     *   the API call fails. Callers should treat this as a hard failure --
     *   never fall back to a fake session id.
     */
    suspend fun createOrder(
        amountRupees: Double,
        orderId: String,
        customerId: String,
        customerPhone: String,
        customerEmail: String? = null,
        notifyUrl: String? = null,
        returnUrl: String? = null
    ): CashfreeOrderResult {
        if (appId.isBlank() || secretKey.isBlank()) {
            throw CashfreeOrderCreationException(
                "Cashfree API keys not configured (youpi.cashfree.app-id / secret-key)"
            )
        }

        val effectiveNotifyUrl = notifyUrl ?: defaultNotifyUrl.ifBlank { null }

        return try {
            post("/orders")
                .bodyValue(
                    mapOf(
                        "order_id" to orderId,
                        "order_amount" to amountRupees,
                        "order_currency" to "INR",
                        "customer_details" to CashfreeCustomerDetails(
                            customerId = customerId,
                            customerPhone = customerPhone,
                            customerEmail = customerEmail
                        ),
                        "order_meta" to CashfreeOrderMeta(
                            returnUrl = returnUrl,
                            notifyUrl = effectiveNotifyUrl
                        )
                    )
                )
                .retrieve()
                .awaitBody<CashfreeOrderResult>()
        } catch (e: Exception) {
            log.error("Cashfree order creation failed for orderId={}: {}", orderId, e.message)
            throw CashfreeOrderCreationException("Cashfree order creation failed: ${e.message}")
        }
    }

    /**
     * Refunds a payment against an existing order. Used when payment
     * succeeded but the downstream service (e.g. A1Topup recharge
     * delivery) failed -- same auto-refund contract as RazorpayClient.refund().
     *
     * @param orderId the Cashfree order_id (NOT a payment id -- unlike
     *   Razorpay, Cashfree refunds are issued against the order).
     * @param refundId your own unique reference for THIS refund attempt --
     *   required by Cashfree, acts as the idempotency key for the refund
     *   call itself (retrying with the same refundId is safe).
     * @param amountRupees the amount to refund, in rupees.
     * @throws CashfreeRefundException if keys aren't configured or the API
     *   call fails. Callers MUST NOT swallow this silently -- same as
     *   Razorpay, a failed refund call means the customer is still owed
     *   money and needs a manual ops follow-up.
     */
    suspend fun refund(
        orderId: String,
        refundId: String,
        amountRupees: Double,
        refundNote: String? = null
    ): CashfreeRefundResult {
        if (appId.isBlank() || secretKey.isBlank()) {
            throw CashfreeRefundException(
                "Cashfree API keys not configured (youpi.cashfree.app-id / secret-key)"
            )
        }

        val body = buildMap<String, Any> {
            put("refund_amount", amountRupees)
            put("refund_id", refundId)
            refundNote?.let { put("refund_note", it) }
        }

        return try {
            post("/orders/$orderId/refunds")
                .bodyValue(body)
                .retrieve()
                .awaitBody<CashfreeRefundResult>()
        } catch (e: Exception) {
            log.error("Cashfree refund failed for orderId={}, refundId={}: {}", orderId, refundId, e.message)
            throw CashfreeRefundException("Cashfree refund failed: ${e.message}")
        }
    }

    /**
     * Fetches current order status directly from Cashfree -- used by the
     * wallet top-up sweeper (WalletService.sweepPendingTopups()) as a
     * missed-webhook safety net. Returns order_status only (Cashfree's
     * order-status API doesn't include a payment id in this response --
     * that lives in the separate /orders/{id}/payments endpoint, not
     * needed here since the sweeper only needs to know PAID vs not).
     */
    suspend fun getOrderStatus(orderId: String): CashfreeOrderResult {
        if (appId.isBlank() || secretKey.isBlank()) {
            throw CashfreeOrderCreationException(
                "Cashfree API keys not configured (youpi.cashfree.app-id / secret-key)"
            )
        }

        return try {
            webClient.get()
                .uri("$baseUrl/orders/$orderId")
                .header("x-client-id", appId)
                .header("x-client-secret", secretKey)
                .header("x-api-version", apiVersion)
                .retrieve()
                .awaitBody<CashfreeOrderResult>()
        } catch (e: Exception) {
            log.error("Cashfree order status fetch failed for orderId={}: {}", orderId, e.message)
            throw CashfreeOrderCreationException("Cashfree order status fetch failed: ${e.message}")
        }
    }
}