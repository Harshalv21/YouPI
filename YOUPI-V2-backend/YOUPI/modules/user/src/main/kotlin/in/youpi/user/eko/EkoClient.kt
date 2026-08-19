package `in`.youpi.user.eko

import `in`.youpi.core.ExternalServiceException
import com.fasterxml.jackson.databind.ObjectMapper
import kotlinx.coroutines.reactor.awaitSingle
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient
import java.time.Instant
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.Base64
import kotlin.random.Random

/**
 * Eko Platform Services client — PAN verification (fetch-pan) and bank
 * account verification (bank-account/sync).
 *
 * Confirmed against Eko's actual Tools/KYC API docs (2026-08-19):
 *   - fetch-pan:          POST /tools/kyc/fetch-pan
 *   - bank-account/sync:  POST /tools/kyc/bank-account/sync
 *
 * UAT base: https://staging.eko.in/ekoapi/v3
 * PRODUCTION base: https://api.eko.in/ekoicici/v3 -- per Eko's official
 * "Environments & auth" docs page (confirmed 2026-08-19, explicitly shows
 * this exact namespace with a /tools/kyc/pan-lite example). NOTE: this
 * conflicts with the base URL given in the original partner credentials
 * email (https://api.eko.in:25002/ekoicici, no /v3) -- that email's own
 * example URL was a DIFFERENT, older-style endpoint
 * (.../v1/customers/mobile_number:.../balance), suggesting it describes a
 * separate/legacy Eko product surface, not this Tools/KYC namespace.
 * Empirically: hitting :25002/ekoicici/v3/tools/kyc/fetch-pan DID reach a
 * real JBossWeb app server (got a real 403 Forbidden page from it) --
 * hitting api.eko.in/ekoicici/v3 (no port, this docs-documented URL)
 * returned 204 No Content from "Google Frontend" instead, which looked
 * like it never reached Eko's actual backend. Root cause of that 204 is
 * still unconfirmed (could be the same IP-whitelist issue manifesting
 * differently at a different gateway layer, or something else) --
 * defaulting to the DOCS-documented URL below since it's the officially
 * supported one, but flagging this discrepancy for Eko support to
 * clarify once the IP whitelist question is resolved.
 *
 * AUTH: developer_key + secret-key + secret-key-timestamp headers on every
 * call, regenerated fresh per request (see generateSecretKey()). NEITHER
 * fetch-pan NOR bank-account/sync use a request_hash header in Eko's
 * documented examples -- that header appears to be reserved for actual
 * money-movement APIs (e.g. Bill Payment), not KYC verification calls.
 */
@Component
class EkoClient(
    @Value("\${youpi.eko.base-url:https://api.eko.in/ekoicici/v3}") private val baseUrl: String,
    @Value("\${youpi.eko.developer-key}") private val developerKey: String,
    @Value("\${youpi.eko.initiator-id}") private val initiatorId: String,
    @Value("\${youpi.eko.authenticator-key}") private val authenticatorKey: String,
    private val objectMapper: ObjectMapper
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private val webClient: WebClient = WebClient.builder()
        .baseUrl(baseUrl)
        .build()

    companion object {
        private const val HMAC_SHA256 = "HmacSHA256"
    }

    // IMPORTANT: per Eko's own PHP/Java/Python samples, the HMAC key is the
    // UTF-8 bytes of the BASE64-ENCODED authenticator key STRING -- not the
    // raw bytes you'd get by base64-decoding it back. e.g. PHP:
    // hash_hmac('SHA256', $timestamp, $encodedKey) where $encodedKey is
    // itself already base64_encode($access_key), used as-is (its own
    // string bytes), never decoded again.
    private fun hmacSha256Base64(message: String, base64EncodedKeyString: String): String {
        val keyBytes = base64EncodedKeyString.toByteArray(Charsets.UTF_8)
        val mac = Mac.getInstance(HMAC_SHA256)
        mac.init(SecretKeySpec(keyBytes, HMAC_SHA256))
        val hash = mac.doFinal(message.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(hash)
    }

    /** MUST be regenerated for every request -- never cache/reuse. */
    private fun generateSecretKey(): Pair<String, String> {
        val encodedAuthenticatorKey = Base64.getEncoder()
            .encodeToString(authenticatorKey.toByteArray(Charsets.UTF_8))
        val timestamp = Instant.now().toEpochMilli().toString()
        val secretKey = hmacSha256Base64(timestamp, encodedAuthenticatorKey)
        return secretKey to timestamp
    }

    /** Per-request idempotency/tracking id -- Eko's samples show a
     * timestamp-shaped string but don't document a strict format
     * requirement, so this generates a unique-enough value: current
     * epoch millis + a 4-digit random suffix. */
    private fun generateClientRefId(): String =
        "${Instant.now().toEpochMilli()}${Random.nextInt(1000, 9999)}"

    private suspend fun doPost(path: String, body: Map<String, Any?>): String {
        val (secretKey, timestamp) = generateSecretKey()
        return try {
            webClient.post()
                .uri(path)
                .header("developer_key", developerKey)
                .header("secret-key", secretKey)
                .header("secret-key-timestamp", timestamp)
                .header("content-type", "application/json")
                .bodyValue(body)
                .retrieve()
                .bodyToMono(String::class.java)
                .awaitSingle()
        } catch (e: Exception) {
            log.error("Eko API call failed: path={}", path, e)
            throw ExternalServiceException("Eko", "Call to $path failed: ${e.message}", e)
        }
    }

    // ── PAN Verification (fetch-pan) ──
    suspend fun verifyPan(panNumber: String): EkoPanVerifyResult {
        val clientRefId = generateClientRefId()
        val response = doPost(
            path = "/tools/kyc/fetch-pan",
            body = mapOf(
                "initiator_id" to initiatorId,
                "client_ref_id" to clientRefId,
                "pan_number" to panNumber,
                "source" to "API"
            )
        )
        val root = objectMapper.readTree(response)
        val data = root.path("data")

        // Two success signals in Eko's response: top-level "status": 0
        // (the API call itself succeeded) AND data.status == "success"
        // (the PAN was actually found/valid) -- both must hold.
        val callSucceeded = root.path("status").asInt(-1) == 0
        val panValid = data.path("status").asText("") == "success"

        return EkoPanVerifyResult(
            success = callSucceeded && panValid,
            nameOnPan = data.path("fullname").asText(null),
            upstreamRrn = data.path("upstream_rrn").asText(null),
            rawResponse = response
        )
    }

    // ── Bank Account Verification (bank-account/sync) ──
    suspend fun verifyBankAccount(accountNumber: String, ifsc: String): EkoBankVerifyResult {
        val clientRefId = generateClientRefId()
        val response = doPost(
            path = "/tools/kyc/bank-account/sync",
            body = mapOf(
                "initiator_id" to initiatorId,
                "client_ref_id" to clientRefId,
                // Eko's sample sends this as a numeric literal, not a
                // string -- worth confirming leading zeros in real account
                // numbers survive their parsing; flagging rather than
                // silently risking truncation.
                "bank_account" to accountNumber,
                "ifsc" to ifsc
            )
        )
        val root = objectMapper.readTree(response)
        val data = root.path("data")

        val callSucceeded = root.path("status").asInt(-1) == 0
        val accountExists = data.path("account_exists").asBoolean(false)

        return EkoBankVerifyResult(
            success = callSucceeded && accountExists,
            accountHolderName = data.path("account_name").asText(null),
            bankName = data.path("bank").asText(null),
            branch = data.path("branch").asText(null),
            utr = data.path("utr").asText(null),
            rawResponse = response
        )
    }
}

data class EkoPanVerifyResult(
    val success: Boolean,
    val nameOnPan: String?,
    val upstreamRrn: String?,
    val rawResponse: String
)

data class EkoBankVerifyResult(
    val success: Boolean,
    val accountHolderName: String?,
    val bankName: String?,
    val branch: String?,
    val utr: String?,
    val rawResponse: String
)