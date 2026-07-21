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
import reactor.netty.http.client.HttpClient
import java.time.Duration
import java.util.concurrent.TimeUnit

/**
 * A1Topup recharge-delivery client.
 *
 * Built against https://a1topup.com/api/prepaid-mobile-recharge --
 * IMPORTANT: that page shows TWO different API docs for what claims to be
 * the same endpoint:
 *   1. business.a1topup.com/recharge/api  (username + pwd)
 *   2. a1topup.com/api/v1/recharge        (api_key)
 * We're using (1) because that's what application.yml already had
 * configured (youpi.a1topup.base-url) before this client existed --
 * presumably confirmed correct during original vendor onboarding. If real
 * calls consistently fail auth, it's worth double-checking with A1Topup
 * support which variant is actually live.
 *
 * KNOWN GAP: the success/error response *shape* shown on their docs site
 * belongs to variant (2), not this one -- variant (1)'s docs page only
 * showed request parameters, not a confirmed response schema. Response
 * parsing below is intentionally defensive (raw string + best-effort field
 * extraction) until a real test call confirms the actual response shape.
 * Once confirmed, tighten `A1TopupRechargeResult` to a proper typed model.
 */
@Component
class A1TopupClient(
    @Value("\${youpi.a1topup.base-url}") private val baseUrl: String,
    @Value("\${youpi.a1topup.username:}") private val username: String,
    @Value("\${youpi.a1topup.password:}") private val password: String,
    private val objectMapper: ObjectMapper
) {

    private val log = LoggerFactory.getLogger(javaClass)

    private val webClient: WebClient = WebClient.builder()
        .baseUrl(baseUrl)
        .clientConnector(
            ReactorClientHttpConnector(
                HttpClient.create()
                    // Connection establishment timeout -- separate from
                    // response timeout below; catches DNS/connect-level hangs.
                    .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5_000)
                    // Overall time to wait for A1Topup's full response after
                    // the request is sent. Without this, a vendor-side hang
                    // ties up the calling coroutine (and the webhook request
                    // that triggered it) indefinitely.
                    .responseTimeout(Duration.ofSeconds(15))
                    .doOnConnected { conn ->
                        conn.addHandlerLast(ReadTimeoutHandler(15, TimeUnit.SECONDS))
                            .addHandlerLast(WriteTimeoutHandler(15, TimeUnit.SECONDS))
                    }
                    // Explicit, not relying on root logging config: this
                    // client sends username/password as query params (vendor-
                    // mandated GET format, no alternative). Wire-logging must
                    // stay off for THIS client specifically regardless of
                    // whatever reactor.netty/webclient log level is set
                    // elsewhere, so credentials can never leak into logs via
                    // a broad DEBUG/TRACE turned on for debugging something
                    // unrelated.
                    .wiretap(false)
            )
        )
        .build()

    companion object {
        // Confirmed from A1Topup's actual operator-code table (their
        // dashboard, not the marketing docs page). Only prepaid-mobile
        // relevant entries included -- DTH/Postpaid codes exist in their
        // table too but aren't used by this recharge module.
        //
        // ⚠️ "VI" is intentionally NOT mapped: post-merger, Vodafone and
        // Idea are marketed as one brand ("Vi"), but A1Topup's table still
        // only lists the legacy "Vodafone" (V) and "Idea" (I) separately --
        // there's no single "VI" row. Passing "VI" straight through would
        // throw (safe), but which legacy code actually matches a given
        // Vi SIM depends on the original operator before the merger, which
        // we can't determine from the number alone. Needs A1Topup to
        // confirm how they want merged-brand numbers submitted before this
        // is wired -- don't guess V vs I here.
        private val CONFIRMED_OPERATOR_CODES = mapOf(
            "AIRTEL" to "A",
            "JIO" to "RC",       // table shows "RELIANCE - JIO", code RC (not "J")
            "VODAFONE" to "V",   // legacy brand, pre-merger only
            "IDEA" to "I",       // legacy brand, pre-merger only
            "BSNL" to "BT"       // "BSNL - TOPUP" = prepaid recharge; "BSNL - STV" (BR) is a separate special-tariff-voucher product, not used here
            // "VI" deliberately omitted -- see comment above
        )

        // Confirmed from A1Topup's circle-code table. Keyed by the exact
        // state/circle label they use, since that's the only thing we can
        // match without guessing. Our RechargeViewModel currently uses
        // "UP East" as its circle value, which matches "Uttar Pradesh East"
        // below via the alias map.
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
            // Common aliases our app might use for the same circles:
            "UP EAST" to "10", "UP WEST" to "11", "J&K" to "25"
        )
    }

    /**
     * Delivers a prepaid recharge via A1Topup.
     *
     * @param orderId our internal recharge order ID, sent as A1Topup's
     *        required `orderid` param -- this is what makes retries safe on
     *        their end (idempotency by their definition, not just ours).
     */
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

        // circlecode is REQUIRED in practice -- their docs mark it optional,
        // but live testing confirmed omitting it causes a generic
        // "Parameter is missing" failure. Don't silently skip it.
        val circleCode = circle?.let { CONFIRMED_CIRCLE_CODES[it.uppercase()] }
            ?: throw ExternalServiceException(
                "A1Topup",
                "No confirmed A1Topup circle code for '$circle' -- circlecode is required " +
                        "(their docs incorrectly mark it optional). Check CONFIRMED_CIRCLE_CODES."
            )

        if (username.isBlank() || password.isBlank()) {
            throw ExternalServiceException("A1Topup", "A1Topup username/password not configured")
        }

        // A1Topup only accepts whole rupees (their own sample requests never
        // show paise, e.g. "10" not "10.50"). Silently truncating via
        // toBigInteger() would send the WRONG amount to the vendor with no
        // error -- a real money mismatch (we'd charge the user ₹10.50 via
        // Razorpay but only request a ₹10 recharge from A1Topup). Reject
        // fractional amounts explicitly instead of guessing how to round.
        if (amount.stripTrailingZeros().scale() > 0) {
            throw ExternalServiceException(
                "A1Topup",
                "Recharge amount $amount has fractional paise -- A1Topup only accepts whole rupees. " +
                        "Refusing to silently truncate and risk a payment/delivery mismatch."
            )
        }

        // A1Topup's own "Sample Request" uses GET with query-string params,
        // and live testing confirmed GET works while POST form-body gave a
        // generic "Parameter is missing" regardless of which params were
        // sent -- so GET is what we use, not "GET/POST" interchangeably as
        // their docs technically claim.
        //
        // IMPORTANT: pass RAW (unencoded) values via .queryParam() inside
        // the UriBuilder-function form, not a manually URLEncoder-encoded
        // string via .uri(String). The latter double-encodes: WebClient's
        // .uri(String) treats the string as a URI template and applies its
        // own encoding pass, so an already-escaped "%24" (from encoding "$"
        // ourselves) becomes "%2524" on the wire -- silently corrupting the
        // password before A1Topup even sees it. This was confirmed the
        // likely cause of a real "Authentication fail!" even with verified-
        // correct credentials and IP whitelisting.
        val rawResponse = try {
            webClient.get()
                .uri { builder ->
                    builder
                        .queryParam("username", username)
                        .queryParam("pwd", password)
                        .queryParam("circlecode", circleCode)
                        .queryParam("operatorcode", operatorCode)
                        .queryParam("number", mobileNumber)
                        // Whole rupees only, e.g. "10" not "10.00" -- matches
                        // their documented example format. Safe now: the
                        // fractional-amount check above already rejected
                        // anything with paise before we get here.
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
     * Parses A1Topup's confirmed response schema (verified via live testing
     * against business.a1topup.com/recharge/api, format=json):
     *   Success: {"txid":"5804","status":"Success","opid":"<operator txn id>","number":"...","amount":"...","orderid":"..."}
     *   Failure: {"txid":"0","status":"Failure","opid":"<human-readable reason>","number":"...","amount":"...","orderid":"..."}
     *   Pending: {"txid":"...","status":"Pending","opid":...,...} -- legitimate
     *            async state, not an error. needsStatusCheck=true tells the
     *            caller to follow up via the Status API later.
     * Note "opid" is overloaded -- it's the operator's transaction reference
     * on success, but carries the failure reason as free text on failure
     * (confirmed live: opid="Invalid IP 115.96.218.57" for a rejected call).
     */
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
                    errorMessage = opid // carries the human-readable reason on failure
                )
                "Pending" -> {
                    // Expected, legitimate async state -- A1Topup is still
                    // processing. Not an error, so INFO not WARN; the caller
                    // (needsStatusCheck=true) knows to follow up later via
                    // the Status API rather than treating this as a failure.
                    log.info("A1Topup: recharge pending for orderId={}, txid={}", orderId, txnId)
                    A1TopupRechargeResult(
                        success = false, transactionId = txnId, rawResponse = raw, needsStatusCheck = true
                    )
                }
                else -> {
                    // Response parsed as JSON but status isn't any of the
                    // three known values -- genuinely unrecognized, so this
                    // one does warrant a WARN. Don't guess, flag for the
                    // Status API to be checked instead of assuming success.
                    log.warn("A1Topup: unrecognized response shape for orderId={}, raw={}", orderId, raw)
                    A1TopupRechargeResult(success = false, transactionId = txnId, rawResponse = raw, needsStatusCheck = true)
                }
            }
        } catch (e: Exception) {
            // Not valid JSON (maybe plain text/XML despite format=json) --
            // don't fail the whole flow on a parse error alone; the HTTP
            // call itself succeeded, so flag it for manual/Status-API
            // follow-up rather than silently marking it failed.
            log.warn("A1Topup: response wasn't valid JSON for orderId={}, raw={}", orderId, raw)
            A1TopupRechargeResult(success = false, transactionId = null, rawResponse = raw, needsStatusCheck = true)
        }
    }
}

data class A1TopupRechargeResult(
    val success: Boolean,
    val transactionId: String?,
    val rawResponse: String,
    // true when we genuinely don't know the outcome yet (unparseable/
    // unrecognized response, or a legitimate Pending) -- caller should
    // treat this differently from a confirmed failure, e.g. by checking
    // A1Topup's Status API rather than assuming the recharge didn't go
    // through.
    val needsStatusCheck: Boolean = false,
    val errorMessage: String? = null
)