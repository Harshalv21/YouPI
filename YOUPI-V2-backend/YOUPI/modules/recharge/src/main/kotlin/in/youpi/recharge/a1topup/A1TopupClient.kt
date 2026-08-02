package `in`.youpi.recharge.a1topup

import com.fasterxml.jackson.databind.ObjectMapper
import `in`.youpi.core.ExternalServiceException
import io.netty.channel.ChannelOption
import io.netty.handler.timeout.ReadTimeoutHandler
import io.netty.handler.timeout.WriteTimeoutHandler
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.client.reactive.ReactorClientHttpConnector
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient
import org.springframework.web.reactive.function.client.awaitBody
import org.springframework.web.util.UriComponentsBuilder
import reactor.netty.http.client.HttpClient
import reactor.netty.transport.ProxyProvider
import java.time.Duration
import java.util.concurrent.TimeUnit

@Component
class A1TopupClient(
    @Value("\${youpi.a1topup.base-url}") private val baseUrl: String,
    // Status/Enquiry API lives at a DIFFERENT path (/recharge/status) than
    // the recharge-submission API (/recharge/api) -- both are siblings
    // under the same domain, /recharge/status is NOT a child of base-url.
    // Kept as a separate config value rather than deriving it by string-
    // manipulating base-url, since that would silently break if base-url's
    // shape ever changes.
    @Value("\${youpi.a1topup.status-url}") private val statusUrl: String,
    @Value("\${youpi.a1topup.username:}") private val username: String,
    @Value("\${youpi.a1topup.password:}") private val password: String,
    @Value("\${youpi.proxy.enabled:true}") private val proxyEnabled: Boolean,
    @Value("\${youpi.proxy.host:10.160.0.2}") private val proxyHost: String,
    @Value("\${youpi.proxy.port:3128}") private val proxyPort: Int,
    private val objectMapper: ObjectMapper
) {

    private val log = LoggerFactory.getLogger(javaClass)

    private val webClient: WebClient = WebClient.builder()
        .baseUrl(baseUrl)
        .clientConnector(
            ReactorClientHttpConnector(
                HttpClient.create()
                    .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5_000)
                    .responseTimeout(Duration.ofSeconds(15))
                    .doOnConnected { conn ->
                        conn.addHandlerLast(ReadTimeoutHandler(15, TimeUnit.SECONDS))
                            .addHandlerLast(WriteTimeoutHandler(15, TimeUnit.SECONDS))
                    }
                    .wiretap(false)
                    .let { client ->
                        if (proxyEnabled) {
                            log.info("A1TopupClient: routing via proxy {}:{}", proxyHost, proxyPort)
                            client.proxy { proxySpec ->
                                proxySpec.type(ProxyProvider.Proxy.HTTP)
                                    .host(proxyHost)
                                    .port(proxyPort)
                            }
                        } else {
                            client
                        }
                    }
            )
        )
        .build()

    // Separate, unbound WebClient for the Status API -- deliberately NOT
    // built with .baseUrl(), since we pass a fully-absolute URI per call
    // (see checkStatus below) and don't want any base-URL prefixing to
    // interfere with that. Same connector settings (timeouts, proxy) as
    // the main client -- Status API goes through the same whitelisted
    // proxy IP as the recharge API, so it needs the same routing.
    private val statusWebClient: WebClient = WebClient.builder()
        .clientConnector(
            ReactorClientHttpConnector(
                HttpClient.create()
                    .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5_000)
                    .responseTimeout(Duration.ofSeconds(15))
                    .doOnConnected { conn ->
                        conn.addHandlerLast(ReadTimeoutHandler(15, TimeUnit.SECONDS))
                            .addHandlerLast(WriteTimeoutHandler(15, TimeUnit.SECONDS))
                    }
                    .wiretap(false)
                    .let { client ->
                        if (proxyEnabled) {
                            client.proxy { proxySpec ->
                                proxySpec.type(ProxyProvider.Proxy.HTTP)
                                    .host(proxyHost)
                                    .port(proxyPort)
                            }
                        } else {
                            client
                        }
                    }
            )
        )
        .build()

    companion object {
        private val CONFIRMED_OPERATOR_CODES = mapOf(
            "AIRTEL" to "A",
            "JIO" to "RC",
            "VODAFONE" to "V",
            "IDEA" to "I",
            "BSNL" to "BT",
            "VI" to "VI"
        )

        private val CONFIRMED_CIRCLE_CODES = mapOf(
            "ANDHRA PRADESH" to "13", "ASSAM" to "24", "BIHAR" to "17",
            "CHHATTISGARH" to "27", "GUJARAT" to "12", "HARYANA" to "20",
            "HIMACHAL PRADESH" to "21", "JAMMU AND KASHMIR" to "25",
            "JHARKHAND" to "22", "KARNATAKA" to "9", "KERALA" to "14",
            "MADHYA PRADESH" to "16", "MAHARASHTRA" to "4", "ORISSA" to "23",
            "PUNJAB" to "1", "RAJASTHAN" to "18", "TAMIL NADU" to "8",
            "UTTAR PRADESH EAST" to "10", "UTTAR PRADESH WEST" to "11",
            "WEST BENGAL" to "2", "MUMBAI" to "3", "DELHI" to "5",
            "CHENNAI" to "7", "NORTH EAST" to "26", "KOLKATA" to "6",
            "UP EAST" to "10", "UP WEST" to "11", "J&K" to "25"
        )

        // Space/hyphen/underscore-stripped version of CONFIRMED_CIRCLE_CODES'
        // keys, built once at class-load time. Needed because
        // RechargeService.kt's detectOperator() now returns circle values in
        // separator-free form (e.g. "UPEAST", after the BSNL circle-spacing
        // bugfix on 31 July 2026 -- mPlan's "circle" field had inconsistent
        // spacing across operators, "UP East" for JIO but "UPEast" for BSNL,
        // which is why matching got normalized to ignore separators entirely
        // rather than trying to enforce one canonical spacing). Looking up
        // circle codes here must use the SAME separator-stripping so a
        // circle value already normalized upstream still matches this map's
        // human-readable (spaced) keys.
        private val NORMALIZED_CIRCLE_CODES: Map<String, String> =
            CONFIRMED_CIRCLE_CODES.mapKeys { (key, _) -> stripSeparators(key) }

        private fun stripSeparators(s: String): String =
            s.trim().uppercase().replace(Regex("[\\s_-]+"), "")
    }

    suspend fun rechargeMobile(
        mobileNumber: String,
        operator: String,
        circle: String?,
        amount: java.math.BigDecimal,
        orderId: String
    ): A1TopupRechargeResult {
        val operatorCode = CONFIRMED_OPERATOR_CODES[operator.uppercase()]
            ?: throw ExternalServiceException(
                "A1Topup",
                "No confirmed A1Topup operator code for '$operator' -- only AIRTEL/JIO/VODAFONE/IDEA/BSNL are mapped. " +
                        "'VI' specifically needs A1Topup to confirm which legacy code (V or I) to use for merged-brand numbers."
            )

        val circleCode = circle?.let { NORMALIZED_CIRCLE_CODES[stripSeparators(it)] }
            ?: throw ExternalServiceException(
                "A1Topup",
                "No confirmed A1Topup circle code for '$circle' -- circlecode is required " +
                        "(their docs incorrectly mark it optional). Check CONFIRMED_CIRCLE_CODES."
            )

        if (username.isBlank() || password.isBlank()) {
            throw ExternalServiceException("A1Topup", "A1Topup username/password not configured")
        }

        if (amount.stripTrailingZeros().scale() > 0) {
            throw ExternalServiceException(
                "A1Topup",
                "Recharge amount $amount has fractional paise -- A1Topup only accepts whole rupees. " +
                        "Refusing to silently truncate and risk a payment/delivery mismatch."
            )
        }

        // Log the outgoing request (excluding username/password) so a
        // failed/pending recharge can be debugged from what we actually
        // sent, not just what A1Topup sent back.
        log.info(
            "A1Topup: sending recharge request for orderId={}: operatorCode={}, circleCode={}, number={}, amount={}",
            orderId, operatorCode, circleCode, mobileNumber, amount.toBigInteger()
        )

        val rawResponse = try {
            webClient.get()
                .uri { builder ->
                    builder
                        .queryParam("username", username)
                        .queryParam("pwd", password)
                        .queryParam("circlecode", circleCode)
                        .queryParam("operatorcode", operatorCode)
                        .queryParam("number", mobileNumber)
                        .queryParam("amount", amount.toBigInteger().toString())
                        .queryParam("orderid", orderId)
                        .queryParam("format", "json")
                        .build()
                }
                .retrieve()
                .awaitBody<String>()
        } catch (e: Exception) {
            log.error("A1Topup: recharge call failed for orderId={}, mobile={}", orderId, mobileNumber, e)
            throw ExternalServiceException("A1Topup", "Recharge request failed: ${e.message}", e)
        }

        log.info("A1Topup: raw response for orderId={}: {}", orderId, rawResponse)

        return parseResponse(rawResponse, orderId)
    }

    /**
     * Follows up on a `Pending` recharge via A1Topup's Status/Enquiry API
     * (business.a1topup.com/recharge/status). Returns the same result shape
     * as rechargeMobile() -- Success/Failure/Pending are parsed identically,
     * since the Status API's response format matches the Recharge API's
     * (per A1Topup's docs: same txid/status/opid/number/amount/orderid
     * shape, just format=json).
     *
     * Called from RechargeService's reconciliation job for orders still
     * sitting in PENDING_VERIFICATION -- NOT called inline during the
     * original webhook handling (A1Topup needs time to actually resolve
     * the transaction on their end; calling this immediately after a
     * `Pending` response would likely just get another `Pending` back).
     */
    suspend fun checkStatus(orderId: String): A1TopupRechargeResult {
        if (username.isBlank() || password.isBlank()) {
            throw ExternalServiceException("A1Topup", "A1Topup username/password not configured")
        }

        // Absolute URI built explicitly (not via a .baseUrl()-bound client)
        // -- statusUrl is a sibling path to base-url
        // (.../recharge/status vs .../recharge/api), not a child of it.
        val uri = UriComponentsBuilder.fromHttpUrl(statusUrl)
            .queryParam("username", username)
            .queryParam("pwd", password)
            .queryParam("orderid", orderId)
            .queryParam("format", "json")
            .build()
            .toUri()

        log.info("A1Topup: checking status for orderId={}", orderId)

        val rawResponse = try {
            statusWebClient.get()
                .uri(uri)
                .retrieve()
                .awaitBody<String>()
        } catch (e: Exception) {
            log.error("A1Topup: status check call failed for orderId={}", orderId, e)
            throw ExternalServiceException("A1Topup", "Status check failed: ${e.message}", e)
        }

        log.info("A1Topup: status check raw response for orderId={}: {}", orderId, rawResponse)

        return parseResponse(rawResponse, orderId)
    }

    private fun parseResponse(raw: String, orderId: String): A1TopupRechargeResult {
        return try {
            val parsed = objectMapper.readValue(raw, Map::class.java)
            val status = (parsed["status"] as? String)
            val txnId = parsed["txid"] as? String
            val opid = parsed["opid"] as? String

            when (status) {
                "Success" -> A1TopupRechargeResult(
                    success = true, transactionId = txnId, rawResponse = raw, needsStatusCheck = false
                )
                "Failure" -> A1TopupRechargeResult(
                    success = false, transactionId = txnId, rawResponse = raw, needsStatusCheck = false,
                    errorMessage = opid
                )
                "Pending" -> {
                    log.info("A1Topup: recharge pending for orderId={}, txid={}", orderId, txnId)
                    A1TopupRechargeResult(
                        success = false, transactionId = txnId, rawResponse = raw, needsStatusCheck = true
                    )
                }
                else -> {
                    log.warn("A1Topup: unrecognized response shape for orderId={}, raw={}", orderId, raw)
                    A1TopupRechargeResult(success = false, transactionId = txnId, rawResponse = raw, needsStatusCheck = true)
                }
            }
        } catch (_: Exception) {
            log.warn("A1Topup: response wasn't valid JSON for orderId={}, raw={}", orderId, raw)
            A1TopupRechargeResult(success = false, transactionId = null, rawResponse = raw, needsStatusCheck = true)
        }
    }
}

data class A1TopupRechargeResult(
    val success: Boolean,
    val transactionId: String?,
    val rawResponse: String,
    val needsStatusCheck: Boolean = false,
    val errorMessage: String? = null
)