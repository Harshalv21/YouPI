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
    val status: String
)

class RazorpayOrderCreationException(message: String) : RuntimeException(message)

/**
 * Thin client for Razorpay's Orders API.
 *
 * Both PaymentService.createOrder() and RechargeService.createOrder() used
 * to generate a fake order ID (`"order_${UUID.randomUUID()...}"`) instead of
 * actually calling Razorpay. That ID doesn't exist on Razorpay's servers, so
 * the Flutter app's Razorpay checkout SDK would reject it outright -- no real
 * payment could ever complete. This client replaces that stub with a real call.
 *
 * Configure via youpi.razorpay.key-id / youpi.razorpay.key-secret (already
 * present as unset @Value placeholders in both services -- just needs real
 * values in Cloud Run's environment).
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
}