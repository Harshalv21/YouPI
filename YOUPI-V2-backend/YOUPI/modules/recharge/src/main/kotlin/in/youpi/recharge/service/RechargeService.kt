package `in`.youpi.recharge.service

import `in`.youpi.core.Result
import `in`.youpi.core.razorpay.RazorpayClient
import `in`.youpi.core.razorpay.RazorpayOrderCreationException
import `in`.youpi.gold.GoldRewardService
import `in`.youpi.invest.service.InvestService
import `in`.youpi.recharge.a1topup.A1TopupClient
import `in`.youpi.recharge.a1topup.A1TopupRechargeResult
import `in`.youpi.recharge.domain.*
import `in`.youpi.recharge.repository.RechargeEmiEntity
import `in`.youpi.recharge.repository.RechargeEmiRepository
import `in`.youpi.recharge.repository.RechargeOrderEntity
import `in`.youpi.recharge.repository.RechargeOrderRepository
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.readValue
import kotlinx.coroutines.reactor.awaitSingle
import kotlinx.coroutines.reactor.awaitSingleOrNull
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.beans.factory.annotation.Value
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.stereotype.Service
import org.springframework.web.reactive.function.client.WebClient
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

@Service
class RechargeService(
    private val rechargeRepo: RechargeOrderRepository,
    private val emiRepo: RechargeEmiRepository,
    private val redisTemplate: ReactiveStringRedisTemplate,
    private val objectMapper: ObjectMapper,
    // Explicitly the PROXIED bean (see WebClientConfig) -- mPlan enforces
    // IP-whitelisting, and Cloud Run's own outbound IP is unstable, so this
    // call needs to go through the fixed-IP proxy VM. Do NOT switch this
    // back to the plain @Primary webClient bean -- that one is intentionally
    // unproxied (used by Razorpay, which doesn't need/want this).
    @Qualifier("proxiedWebClient") private val webClient: WebClient,
    private val investService: InvestService,                   // ← recharge → auto gold-invest ke liye (LEGACY, disabled this version -- see handleWebhookCaptured)
    private val goldRewardService: GoldRewardService,            // ← recharge → coin-count reward (THIS VERSION's real gold-crediting path)
    private val razorpayClient: RazorpayClient,
    private val a1topupClient: A1TopupClient,
    @Value("\${mplan.api.key}") private val mplanApiKey: String,
    @Value("\${mplan.api.plans-url}") private val mplanPlansUrl: String,
    @Value("\${mplan.api.mobile-plans-url}") private val mplanMobilePlansUrl: String,
    @Value("\${mplan.api.operator-check-url}") private val mplanOperatorCheckUrl: String,
    @Value("\${youpi.recharge.gold-invest-percentage:1.0}") private val goldInvestPercentage: BigDecimal,
    // TEMPORARY -- lets recharge flow (Razorpay checkout, order creation,
    // EMI, etc.) be tested end-to-end while mPlan's "not authorize" issue is
    // under investigation on their end (confirmed vendor-side, not ours --
    // see chat history). Defaults to OFF. MUST be turned off again once
    // mPlan is confirmed working -- do not let this repeat the
    // AUTH_DUMMY_ENABLED situation where a test-only bypass got left on in
    // production. Returns clearly-labeled fake plans, never touches mPlan.
    @Value("\${youpi.recharge.mock-enabled:false}") private val mockEnabled: Boolean
) {
    private val log = LoggerFactory.getLogger(javaClass)

    // TEMPORARY mock plans -- clearly labeled [TEST MOCK] in the description
    // so nobody mistakes these for real mPlan data in logs, screenshots, or
    // demos. Covers enough variety (small/large amounts, EMI-eligible ₹249
    // plan) to exercise the full recharge + payment + gold-auto-invest flow.
    private fun mockPlans(operator: String, circle: String): List<PlanResponse> = listOf(
        PlanResponse(planId = "MOCK0001", operator = operator, circle = circle, amount = BigDecimal("199"),
            validity = "28", description = "[TEST MOCK] Unlimited calls, 1.5GB/day", category = "POPULAR",
            data = null, talktime = null, sms = null),
        PlanResponse(planId = "MOCK0002", operator = operator, circle = circle, amount = BigDecimal("249"),
            validity = "28", description = "[TEST MOCK] Unlimited calls, 2GB/day + gold auto-invest eligible", category = "POPULAR",
            data = null, talktime = null, sms = null),
        PlanResponse(planId = "MOCK0003", operator = operator, circle = circle, amount = BigDecimal("599"),
            validity = "84", description = "[TEST MOCK] Unlimited calls, 2GB/day, long validity", category = "POPULAR",
            data = null, talktime = null, sms = null),
        PlanResponse(planId = "MOCK0004", operator = operator, circle = circle, amount = BigDecimal("3599"),
            validity = "365", description = "[TEST MOCK] Annual unlimited plan", category = "ANNUAL",
            data = null, talktime = null, sms = null)
    )

    companion object {
        private val PLAN_CACHE_TTL = Duration.ofMinutes(30)
        private const val PLAN_CACHE_PREFIX = "plans:"
        // A1Topup pending-reconciliation poll gives up after ~1 hour --
        // handled via createdAt age check in reconcilePendingRecharges(),
        // no separate constant/column needed.

        // THIS VERSION: lowered to ₹20 for coin-count-only testing (no real
        // gold/Augmont investment yet -- that's deferred to the next version
        // once bank API integration lands). Compared with compareTo (not ==)
        // because BigDecimal("20") != BigDecimal("20.00") under equals(),
        // but compareTo treats them as equal in value.
        // MUST STAY IN SYNC with the Flutter check in emi_selection_screen.dart
        // (currently `if (plan.price >= 20)`) -- one drifting from the other
        // means the animation and the actual coin credit disagree.
        private val GOLD_ELIGIBLE_PLAN_AMOUNT = BigDecimal("20")

        // TEMPORARY: A1Topup's recharge-delivery catalog doesn't support
        // mPlan's small data-addon denominations -- confirmed via live
        // testing on 30 July 2026: ₹22 and ₹26 (mPlan data-addon packs)
        // both came back "Transaction Failed" on A1Topup (both via our API
        // path AND via A1Topup's own WEB dashboard -- so this isn't an
        // integration bug, A1Topup genuinely doesn't carry these
        // denominations), while ₹19 and ₹349 (standard recharge
        // denominations) both succeeded. mPlan is a plan-BROWSING catalog;
        // A1Topup is the actual delivery vendor, and their denomination
        // lists don't fully overlap.
        //
        // ₹29 is a conservative floor -- it excludes the two confirmed-bad
        // amounts (22, 26) while still being low enough to likely include
        // most standard small recharges. This is a blunt filter, not a
        // verified denomination list: it may hide some genuinely-valid
        // plans in the ₹29-100ish range, or (less likely, unconfirmed)
        // let through some other unsupported amount above ₹29. Replace
        // with a real cross-check against A1Topup's supported-denomination
        // list once they provide one (asked, pending as of this comment).
        private val MIN_DELIVERABLE_AMOUNT = BigDecimal("29")
    }

    // ── Plan Fetching (Redis Cached) ──

    // mPlan requires numeric operator_code / circle_code, not free-text names.
    // These mappings come from mPlan's dashboard (Operator Codes / Circle
    // Codes tables) -- update here if mPlan adds/changes codes.
    private val operatorCodeMap = mapOf(
        "VI" to 1,
        "AIRTEL" to 2,
        "MTNL" to 3,
        "BSNL" to 4,
        "JIO" to 5
    )

    private val circleCodeMap = mapOf(
        "ANDHRA PRADESH" to 2,
        "ASSAM" to 3,
        "BIHAR JHARKHAND" to 4,
        "DELHI NCR" to 5,
        "GUJARAT" to 6,
        "HIMACHAL PRADESH" to 7,
        "HARYANA" to 8,
        "JAMMU KASHMIR" to 9,
        "KERALA" to 10,
        "KARNATAKA" to 11,
        "KOLKATA" to 12,
        "MAHARASHTRA" to 13,
        "MADHYA PRADESH CHHATTISGARH" to 14,
        "MUMBAI" to 15,
        "NORTH EAST" to 16,
        "ORISSA" to 17,
        "PUNJAB" to 18,
        "RAJASTHAN" to 19,
        "TAMIL NADU" to 20,
        "UP EAST" to 21,
        "UP WEST" to 22,
        "WEST BENGAL" to 23,
        "CHENNAI" to 25
    )

    // Normalizes "UP-East", "up_east", "  UP East " etc. into the map's
    // canonical "UP EAST" form so callers don't have to match punctuation
    // exactly.
    private fun normalizeKey(s: String): String =
        s.trim().uppercase().replace("-", " ").replace("_", " ").replace(Regex("\\s+"), " ")

    suspend fun fetchPlans(operator: String, circle: String): Result<List<PlanResponse>, RechargeException> {
        // TEMPORARY mock short-circuit -- see mockEnabled doc comment above.
        if (mockEnabled) {
            log.warn("MOCK MODE ACTIVE: returning fake plans instead of calling mPlan. " +
                    "This must be disabled (youpi.recharge.mock-enabled=false) before real launch.")
            return Result.success(mockPlans(operator, circle))
        }

        val cacheKey = "$PLAN_CACHE_PREFIX${operator.uppercase()}:${circle.uppercase()}"

        val cached = redisTemplate.opsForValue().get(cacheKey).awaitSingleOrNull()
        if (cached != null) {
            log.debug("Plans cache HIT for {}", cacheKey)
            return try {
                Result.success(objectMapper.readValue(cached))
            } catch (e: Exception) {
                log.warn("Cache deserialization failed for {}, re-fetching", cacheKey, e)
                redisTemplate.delete(cacheKey).awaitSingleOrNull()
                fetchPlansFromApi(operator, circle, cacheKey)
            }
        }

        return fetchPlansFromApi(operator, circle, cacheKey)
    }

    private suspend fun fetchPlansFromApi(
        operator: String,
        circle: String,
        cacheKey: String
    ): Result<List<PlanResponse>, RechargeException> {
        val operatorCode = operatorCodeMap[normalizeKey(operator)]
            ?: return Result.failure(RechargeApiException("Unknown operator: $operator"))
        val circleCode = circleCodeMap[normalizeKey(circle)]
            ?: return Result.failure(RechargeApiException("Unknown circle: $circle"))

        return try {
            // TEMPORARY DIAGNOSTIC -- confirms what outbound IP this exact
            // webClient bean actually uses, right before the mPlan call.
            // Cross-checks against A1Topup (which IS known to egress via
            // youpi-nat-ip successfully) to isolate whether this is a
            // per-call routing issue or a genuine infra problem. Remove
            // once the IP mismatch is root-caused.
            try {
                val myIp = webClient.get()
                    .uri("https://api.ipify.org?format=text")
                    .retrieve()
                    .bodyToMono(String::class.java)
                    .awaitSingle()
                log.error("DIAGNOSTIC: outbound IP for this webClient bean = {}", myIp)
            } catch (e: Exception) {
                log.error("DIAGNOSTIC: ipify check failed", e)
            }

            // IMPORTANT: build the URI via UriComponentsBuilder + .queryParam()
            // + .encode(), not a manually-concatenated string passed to
            // .uri(String). The latter does its own encoding pass over an
            // already-built string -- if mplanApiKey contains characters like
            // '+', '/', or '=' (common in API keys), they can get corrupted
            // or misinterpreted before mPlan ever sees them. This is the same
            // class of bug that caused A1Topup's "Authentication fail!"
            // earlier -- fixed there via the equivalent safe-encoding
            // pattern. .trim() also guards against a trailing newline in the
            // secret (bit the team before with Cloud Run secrets -- see
            // Set-Content -NoNewline fix).
            //
            // Note: this `webClient` bean has no baseUrl configured (it's
            // shared across multiple vendor integrations), so we build a
            // full absolute URI explicitly rather than relying on the
            // uri{builder->} form, which only works against a client-level
            // baseUrl.
            // TEMPORARY DIAGNOSTIC -- verifies the EXACT api key this code
            // sends matches the one manually tested via curl (which
            // succeeds). Masked (not full value) to avoid putting the whole
            // secret in logs, but length + first/last 4 chars is enough to
            // catch a hidden extra character (stray quote/newline/space
            // from Secret Manager) that .trim() wouldn't necessarily catch
            // if it's not at the very start/end after trim, or if trim
            // missed something unexpected. Remove once ruled out.
            val trimmedKey = mplanApiKey.trim()
            log.error(
                "DIAGNOSTIC: mplan api key length={}, first4={}, last4={}",
                trimmedKey.length,
                trimmedKey.take(4),
                trimmedKey.takeLast(4)
            )

            val uri = org.springframework.web.util.UriComponentsBuilder
                .fromHttpUrl(mplanMobilePlansUrl)
                .queryParam("apikey", trimmedKey)
                .queryParam("operator_code", operatorCode)
                .queryParam("circle_code", circleCode)
                .build()
                .encode()
                .toUri()

            log.error("DIAGNOSTIC: exact outgoing URI = {}", uri)

            val response = webClient.get()
                .uri(uri)
                .retrieve()
                .bodyToMono(String::class.java)
                .awaitSingle()

            val root = objectMapper.readTree(response)

            // mPlan returns {"status": 0, "records": {"msg": "..."}} on
            // failure (bad key, bad IP, bad params) and {"status": 1,
            // "records": {<category>: [...plans]}, ...} on success.
            if (root.path("status").asInt(0) != 1) {
                val errorMsg = root.path("records").path("msg").asText("Unknown mPlan API error")
                // TEMPORARY: log the full raw response too -- mPlan's
                // failure response includes a "yourip" field showing
                // exactly which IP it saw the request come from. This is
                // the only way to get DIRECT proof of what IP Cloud Run's
                // outbound traffic actually uses (vs. assuming the NAT IP
                // is correctly applied to this call). Remove this extra
                // log line once the IP is confirmed either way.
                log.error("mPlan API returned failure status: operator={}, circle={}, msg={}, fullResponse={}",
                    operator, circle, errorMsg, response)
                return Result.failure(RechargeApiException("mPlan error: $errorMsg"))
            }

            val plans = mutableListOf<PlanResponse>()
            val recordsNode = root.path("records")

            recordsNode.fields().forEach { (category, plansNode) ->
                if (plansNode.isArray) {
                    plansNode.forEach { plan ->
                        plans.add(PlanResponse(
                            planId = UUID.randomUUID().toString().take(8),
                            operator = operator,
                            circle = circle,
                            amount = BigDecimal(plan.path("rs").asText("0")),
                            validity = plan.path("validity").asText(""),
                            description = plan.path("desc").asText(""),
                            category = category.uppercase(),
                            data = null,
                            talktime = null,
                            sms = null
                        ))
                    }
                }
            }

            // Filter out denominations A1Topup can't actually deliver --
            // see MIN_DELIVERABLE_AMOUNT doc comment above. Done BEFORE
            // caching, so the filtered-out plans never sit in Redis for
            // the 30-min TTL either -- otherwise a cache hit would keep
            // serving undeliverable plans even after this filter is
            // tightened/replaced later.
            val deliverablePlans = plans.filter { it.amount >= MIN_DELIVERABLE_AMOUNT }
            val filteredCount = plans.size - deliverablePlans.size
            if (filteredCount > 0) {
                log.info(
                    "Filtered out {} plan(s) below MIN_DELIVERABLE_AMOUNT ({}) for operator={}, circle={} -- " +
                            "these are mPlan denominations not known to be deliverable via A1Topup",
                    filteredCount, MIN_DELIVERABLE_AMOUNT, operator, circle
                )
            }

            val json = objectMapper.writeValueAsString(deliverablePlans)
            redisTemplate.opsForValue().set(cacheKey, json, PLAN_CACHE_TTL).awaitSingleOrNull()

            log.info("Plans fetched from mPlan API: operator={}, circle={}, count={}", operator, circle, deliverablePlans.size)
            Result.success(deliverablePlans)
        } catch (e: Exception) {
            log.error("mPlan API call failed for operator={}, circle={}", operator, circle, e)
            Result.failure(RechargeApiException("Failed to fetch plans: ${e.message}"))
        }
    }

    // ── Operator Detection (mPlan HLR) ──
    // Response shape confirmed live on 30 July 2026 (after mPlan fixed
    // their whitelist issue):
    //   {"status":1,"mobile_number":"...","records":{"status":1,
    //    "Operator":"Jio","circle":"UP East","comcircle":"UP East",
    //    "OperatorCode":5,"CircleCode":21},"time":5.22}
    // Note the OUTER "status" and the INNER "records.status" -- both need
    // to be 1 for a genuine success; a failure still returns HTTP 200 with
    // outer status=0 and records.msg holding the error (e.g. the
    // "You are not authorize." we chased earlier).
    suspend fun detectOperator(mobileNumber: String): Result<OperatorDetectionResponse, RechargeException> {
        return try {
            val uri = org.springframework.web.util.UriComponentsBuilder
                .fromHttpUrl(mplanOperatorCheckUrl)
                .queryParam("apikey", mplanApiKey.trim())
                .queryParam("mobile_number", mobileNumber)
                .build()
                .encode()
                .toUri()

            val response = webClient.get()
                .uri(uri)
                .retrieve()
                .bodyToMono(String::class.java)
                .awaitSingle()

            val root = objectMapper.readTree(response)
            val records = root.path("records")

            if (root.path("status").asInt(0) != 1 || records.path("status").asInt(0) != 1) {
                val errorMsg = records.path("msg").asText("Unknown mPlan operator-check error")
                log.error("mPlan operator-check failed for mobile={}: {}", mobileNumber, errorMsg)
                return Result.failure(OperatorDetectionException(errorMsg))
            }

            // Normalize through the SAME function used for plan fetching,
            // so "Jio"/"JIO"/"jio" and "UP East"/"UP EAST" all resolve
            // identically and match operatorCodeMap/circleCodeMap exactly.
            val operator = normalizeKey(records.path("Operator").asText(""))
            val circle = normalizeKey(records.path("circle").asText(""))

            if (operator !in operatorCodeMap || circle !in circleCodeMap) {
                log.error(
                    "mPlan operator-check returned unmapped operator/circle: operator={}, circle={}, mobile={}",
                    operator, circle, mobileNumber
                )
                return Result.failure(OperatorDetectionException(
                    "Detected operator/circle not recognized: $operator / $circle"
                ))
            }

            log.info("Operator detected: mobile={}, operator={}, circle={}", mobileNumber, operator, circle)
            Result.success(OperatorDetectionResponse(operator = operator, circle = circle))
        } catch (e: Exception) {
            log.error("mPlan operator-check call failed for mobile={}", mobileNumber, e)
            Result.failure(OperatorDetectionException("Failed to detect operator: ${e.message}"))
        }
    }

    // ── Order Creation ──

    suspend fun createOrder(userId: UUID, req: CreateRechargeRequest): Result<RechargeOrderResponse, RechargeException> {
        // ← fix: duplicate pe exception nahi, existing order return karo
        val existing = rechargeRepo.findByIdempotencyKey(req.idempotencyKey)
        if (existing != null) {
            return Result.success(
                RechargeOrderResponse(
                    orderId = existing.id!!,
                    razorpayOrderId = existing.razorpayOrderId ?: "",
                    amount = existing.planAmount,
                    status = existing.status,
                    paymentMode = existing.paymentMode
                )
            )
        }

        val emiMonths: Short? = when (req.paymentMode) {
            PaymentMode.EMI_3  -> 3
            PaymentMode.EMI_6  -> 6
            PaymentMode.EMI_12 -> 12
            else -> null
        }
        val emiAmount = emiMonths?.let {
            req.planAmount.divide(BigDecimal(it.toInt()), 2, java.math.RoundingMode.CEILING)
        }

        // Call Razorpay BEFORE writing anything to the DB. Previously the
        // order (and EMI schedule rows) were saved first, then patched with
        // a fake razorpayOrderId -- meaning a real API failure here would
        // leave an orphaned "INITIATED" order with no way to actually pay it.
        val amountPaise = req.planAmount.multiply(BigDecimal(100)).toLong()
        val razorpayOrderId = try {
            razorpayClient.createOrder(
                amountPaise = amountPaise,
                receipt = req.idempotencyKey,
                notes = mapOf(
                    "userId" to userId.toString(),
                    "mobileNumber" to req.mobileNumber,
                    "operator" to req.operator
                )
            ).id
        } catch (e: RazorpayOrderCreationException) {
            log.error("Razorpay order creation failed for user={}: {}", userId, e.message)
            return Result.failure(RechargeApiException(e.message ?: "Razorpay order creation failed"))
        }

        val order = rechargeRepo.insertOrder(
            userId = userId,
            mobileNumber = req.mobileNumber,
            operator = req.operator,
            circle = req.circle,
            planId = req.planId,
            planAmount = req.planAmount,
            planDetails = "{}",
            paymentMode = req.paymentMode.name,
            emiMonths = emiMonths,
            emiAmount = emiAmount,
            status = "INITIATED",
            razorpayOrderId = razorpayOrderId,
            goldAutoInvest = false,
            idempotencyKey = req.idempotencyKey,
            planValidityDays = req.planValidityDays
        )

        if (emiMonths != null && emiAmount != null) {
            for (i in 1..emiMonths) {
                emiRepo.save(
                    RechargeEmiEntity(
                        rechargeId = order.id!!,
                        userId = userId,
                        instalmentNo = i.toShort(),
                        dueDate = LocalDate.now().plusMonths(i.toLong()),
                        amount = emiAmount
                    )
                )
            }
        }

        log.info("Recharge order created: orderId={}, amount={}, mode={}, razorpayOrderId={}",
            order.id, req.planAmount, req.paymentMode, razorpayOrderId)

        return Result.success(
            RechargeOrderResponse(
                orderId = order.id!!,
                razorpayOrderId = razorpayOrderId,
                amount = req.planAmount,
                status = "INITIATED",
                paymentMode = req.paymentMode.name
            )
        )
    }

    // ── Webhook-Driven Completion (the ONLY path that grants SUCCESS + gold) ──
    //
    // Previously `confirmRecharge` trusted a client-supplied razorpaySignature
    // to decide SUCCESS -- a client can call any API with any payload it
    // wants, signature included, since the signature is computed from public
    // order/payment IDs the client already has after checkout. That let a
    // malicious client claim success (and get free gold) for a payment that
    // never actually happened. The Razorpay webhook, by contrast, comes
    // straight from Razorpay's servers over a channel only Razorpay holds the
    // secret for -- so it's the only signal we can trust to mutate state.
    //
    // Called from PaymentService's webhook handler once it verifies the
    // request came from Razorpay and finds a recharge order for the
    // razorpay_order_id in the payload.
    suspend fun handleWebhookCaptured(razorpayOrderId: String, razorpayPaymentId: String): Boolean {
        val order = rechargeRepo.findByRazorpayOrderId(razorpayOrderId) ?: run {
            log.debug("Recharge webhook: no recharge order for razorpayOrderId={} (likely a different purpose)", razorpayOrderId)
            return false
        }

        // Idempotency -- Razorpay retries webhooks, and PaymentService may
        // also see the same event via /verify if the client races the
        // webhook. Either way, a second delivery must be a no-op, not a
        // second gold purchase.
        if (order.status != "INITIATED") {
            log.info("Recharge webhook: order already processed (status={}), skipping orderId={}", order.status, order.id)
            return true
        }

        // ── Deliver the actual recharge via A1Topup ──
        var status = "PAYMENT_DONE"
        var a1topupStatus: String
        var a1topupRawResponse: String

        try {
            val result = a1topupClient.rechargeMobile(
                mobileNumber = order.mobileNumber,
                operator = order.operator,
                circle = order.circle,
                amount = order.planAmount,
                orderId = order.id.toString()
            )
            a1topupRawResponse = result.rawResponse

            a1topupStatus = when {
                result.success -> {
                    status = "RECHARGE_SUCCESS"
                    "SUCCESS"
                }
                result.needsStatusCheck -> {
                    // A1Topup accepted the HTTP call but we couldn't confirm
                    // outcome from the response -- do NOT mark RECHARGE_FAILED
                    // here, since the recharge may well have gone through on
                    // their end. Needs their Status API polled to resolve.
                    log.warn("A1Topup: response ambiguous for orderId={}, needs Status API check", order.id)
                    "PENDING_VERIFICATION"
                }
                else -> {
                    status = "RECHARGE_FAILED"
                    log.error("A1Topup: recharge failed for orderId={}, reason={}", order.id, result.errorMessage)
                    "FAILED"
                }
            }
        } catch (e: Exception) {
            // Payment is already captured at this point. Previously this
            // left the order at PAYMENT_DONE forever with no automated
            // resolution -- no Status API integration exists yet to
            // actually confirm what happened on A1Topup's side. Given that,
            // treating this the same as a confirmed failure (attempt
            // refund) is the safer default for the customer: the
            // alternative was an indefinitely stuck order that only gets
            // resolved by a support ticket. Residual risk: if the recharge
            // secretly succeeded despite the thrown exception (e.g. A1Topup
            // processed it but the response got lost in transit), this
            // refunds money for a recharge that did go through. Logged
            // distinctly from the confirmed-failure path below so ops can
            // spot-check these specific cases against A1Topup's own
            // transaction log if needed. TODO: replace with a real A1Topup
            // Status/Enquiry API call once that endpoint is documented --
            // this is a stopgap, not the final fix.
            log.error("A1Topup: recharge call threw for orderId={} -- treating as failure for refund purposes (UNCONFIRMED, see comment)", order.id, e)
            status = "RECHARGE_FAILED"
            a1topupStatus = "FAILED"
            a1topupRawResponse = "error: ${e.message}"
        }

        // ── Auto-refund on confirmed A1Topup failure ──
        // Payment was captured but the recharge itself definitively failed
        // (not "ambiguous, needs status check" -- that case is left alone
        // above since the recharge may still have gone through). The
        // customer paid for something they didn't receive; money must go
        // back automatically, not sit as a silent RECHARGE_FAILED row that
        // nobody notices until a support ticket shows up.
        var refundFailureNote: String? = null
        if (status == "RECHARGE_FAILED") {
            try {
                val refund = razorpayClient.refund(
                    paymentId = razorpayPaymentId,
                    notes = mapOf(
                        "reason" to "recharge_delivery_failed",
                        "rechargeOrderId" to order.id.toString()
                    )
                )
                status = "REFUNDED"
                log.info(
                    "Refund issued for orderId={} after A1Topup failure: refundId={}, status={}",
                    order.id, refund.id, refund.status
                )
            } catch (e: Exception) {
                // Refund itself failed -- this is now a double failure that
                // NEEDS a human: customer paid, recharge failed, AND the
                // automatic refund didn't go through either. Do not let this
                // disappear into a debug log next to routine warnings --
                // keep status as RECHARGE_FAILED (not REFUNDED, that would
                // be a lie) and record the refund attempt's own failure so
                // it's visible on the order itself, not just in logs.
                log.error(
                    "REFUND FAILED for orderId={} after A1Topup failure -- customer still owed money, " +
                            "needs manual refund via Razorpay dashboard. Error: {}",
                    order.id, e.message, e
                )
                refundFailureNote = "Auto-refund failed: ${e.message}. Needs manual refund."
            }
        }

        var updatedOrder = rechargeRepo.updateAfterConfirm(
            id = order.id!!,
            status = status,
            razorpayPaymentId = razorpayPaymentId,
            a1topupStatus = a1topupStatus,
            a1topupRawResponse = toSafeJson(a1topupRawResponse),
            goldAutoInvest = order.goldAutoInvest,
            goldTxnId = order.goldTxnId,
            failureReason = refundFailureNote
        )

        log.info("Recharge confirmed via webhook: orderId={}, amount={}", updatedOrder.id, updatedOrder.planAmount)

        // ── Set expiry on confirmed success ──
        // Only meaningful for a genuinely completed recharge -- REFUNDED,
        // RECHARGE_FAILED, PENDING_VERIFICATION etc. have no real "active
        // until" date, so expiry_date stays null for those (findActiveRecharge
        // only looks at RECHARGE_SUCCESS rows anyway, but leaving it null
        // elsewhere avoids a misleading date sitting on a failed order).
        if (updatedOrder.status == "RECHARGE_SUCCESS" && order.planValidityDays != null && order.planValidityDays > 0) {
            val expiryDate = LocalDate.now().plusDays(order.planValidityDays.toLong())
            rechargeRepo.setExpiryDate(updatedOrder.id!!, expiryDate)
            log.info("Recharge expiry set: orderId={}, expiryDate={}", updatedOrder.id, expiryDate)
        }

        // ── Gold Coin Reward (coin-count only, THIS VERSION) ──
        // Real backend crediting for the coin-count/balance_rupees system.
        // Deliberately gated on RECHARGE_SUCCESS specifically (not
        // PAYMENT_DONE/REFUNDED/PENDING_VERIFICATION) -- don't reward a
        // recharge that didn't actually reach the user. Non-fatal: a
        // gold-crediting failure must never roll back an already-successful
        // recharge; ops can reconcile from the warning in logs. Idempotency
        // is handled inside GoldRewardService itself (ON CONFLICT on
        // recharge_txn_id), so a retried webhook delivery is a safe no-op.
        //
        // Legacy investService.buyGold() (real Augmont money-based gold
        // purchase) stays disabled -- not wanted until bank API integration
        // lands in a future version.
        if (updatedOrder.status == "RECHARGE_SUCCESS") {
            try {
                goldRewardService.creditRewardForRecharge(
                    userId = order.userId,
                    rechargeTxnId = updatedOrder.id.toString(),
                    rechargeAmount = updatedOrder.planAmount
                )
                log.info("Gold coin reward credited (if eligible): orderId={}, planAmount={}",
                    updatedOrder.id, updatedOrder.planAmount)
            } catch (e: Exception) {
                log.warn("Gold coin reward crediting failed (non-fatal): orderId={}, reason={}",
                    updatedOrder.id, e.message)
            }
        }

        return true
    }

    // ── Status Check (client polls this after Razorpay checkout closes) ──
    //
    // The client still calls this right after checkout to know what to show
    // the user, but it no longer MUTATES anything -- it just reports whatever
    // state the webhook has (or hasn't) already written. If the webhook
    // hasn't landed yet (it's usually near-instant, but Razorpay doesn't
    // guarantee ordering vs. the checkout callback), the client sees
    // INITIATED/PENDING and should poll this endpoint for a few seconds
    // rather than treat it as failure.
    suspend fun getConfirmationStatus(userId: UUID, rechargeOrderId: UUID): Result<ConfirmRechargeResponse, RechargeException> {
        val order = rechargeRepo.findById(rechargeOrderId)
            ?: return Result.failure(RechargeOrderNotFoundException(rechargeOrderId))

        if (order.userId != userId) {
            return Result.failure(RechargeOrderNotFoundException(rechargeOrderId))
        }

        val goldEligible = order.planAmount.compareTo(GOLD_ELIGIBLE_PLAN_AMOUNT) >= 0
        val goldAmount = if (goldEligible) {
            order.planAmount.multiply(goldInvestPercentage).divide(BigDecimal(100), 2, java.math.RoundingMode.HALF_EVEN)
        } else null

        return Result.success(
            ConfirmRechargeResponse(
                orderId = order.id!!,
                status = order.status,
                a1TopupStatus = order.a1topupStatus,
                goldAutoInvest = order.goldAutoInvest,
                goldTxnId = order.goldTxnId,
                goldInvestAmount = if (order.goldAutoInvest) goldAmount else null,
                goldWarning = if (goldEligible && !order.goldAutoInvest && order.status != "INITIATED")
                    "Gold investment could not be completed for this recharge" else null
            )
        )
    }

    // ── Active Recharge (home screen status card) ──

    suspend fun getActiveRecharge(userId: UUID): ActiveRechargeResponse? {
        val order = rechargeRepo.findActiveRecharge(userId) ?: return null
        val expiryDate = order.expiryDate ?: return null // shouldn't happen given the query filter, but be defensive

        return ActiveRechargeResponse(
            orderId = order.id!!,
            mobileNumber = order.mobileNumber,
            operator = order.operator,
            planAmount = order.planAmount,
            expiryDate = expiryDate,
            daysRemaining = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.now(), expiryDate).coerceAtLeast(0)
        )
    }

    // ── Get Order Status ──

    suspend fun getOrderStatus(userId: UUID, orderId: UUID): Result<RechargeStatusResponse, RechargeException> {
        val order = rechargeRepo.findById(orderId)
            ?: return Result.failure(RechargeOrderNotFoundException(orderId))

        if (order.userId != userId) {
            return Result.failure(RechargeOrderNotFoundException(orderId))
        }

        return Result.success(
            RechargeStatusResponse(
                orderId = order.id!!,
                status = order.status,
                mobileNumber = order.mobileNumber,
                operator = order.operator,
                planAmount = order.planAmount,
                a1TopupStatus = order.a1topupStatus,
                goldTxnId = order.goldTxnId
            )
        )
    }

    // The a1topup_raw_response column is JSONB (CAST($4 AS jsonb) in the
    // UPDATE) -- A1Topup's actual response might not be valid JSON (their
    // docs mention csv/xml formats too, and our own error messages
    // definitely aren't JSON). Wrapping guarantees a valid JSON value goes
    // into that column no matter what came back, instead of a second
    // "violates ... jsonb" crash like the one 'status' caused earlier.
    private fun toSafeJson(raw: String): String {
        return try {
            objectMapper.readTree(raw) // already valid JSON? use as-is
            raw
        } catch (e: Exception) {
            objectMapper.writeValueAsString(mapOf("raw" to raw))
        }
    }

    // ── History ──

    suspend fun getOrderHistory(userId: UUID, page: Int = 0, pageSize: Int = 20): List<RechargeStatusResponse> {
        return rechargeRepo.findByUserId(userId, pageSize, page * pageSize).map {
            RechargeStatusResponse(
                orderId = it.id!!,
                status = it.status,
                mobileNumber = it.mobileNumber,
                operator = it.operator,
                planAmount = it.planAmount,
                a1TopupStatus = it.a1topupStatus,
                goldTxnId = it.goldTxnId
            )
        }
    }

    // ── A1Topup Pending Resolution (Status API polling + Callback webhook) ──

    /**
     * Callback webhook -- register this URL with A1Topup (MY ACCOUNT ->
     * Callback URL setting on their dashboard) so they push status updates
     * here the moment a pending/disputed transaction resolves, instead of
     * us finding out only via the next poll cycle.
     *
     * Per A1Topup's docs the callback carries txid, status (Success/
     * Failure), and opid as query params -- NOT a JSON body. txid here is
     * OUR orderid (the docs say "along with the Operator ID, Status and
     * txid", and their sample recharge call sends orderid=ours, so txid in
     * the callback is presumed to echo that back -- confirm this against a
     * real callback once A1Topup fires one, their docs are a little terse
     * on this point).
     */
    suspend fun handleA1TopupCallback(orderId: String, status: String, opid: String?) {
        log.info("A1Topup callback received: orderId={}, status={}, opid={}", orderId, status, opid)
        val result = A1TopupRechargeResult(
            success = status.equals("Success", ignoreCase = true),
            transactionId = opid,
            rawResponse = "callback: orderid=$orderId, status=$status, opid=$opid",
            needsStatusCheck = false,
            errorMessage = if (!status.equals("Success", ignoreCase = true)) opid else null
        )
        resolveA1TopupOutcome(orderId, result)
    }

    /**
     * Backup poller -- picks up any order still PENDING_VERIFICATION after
     * 2+ minutes and asks A1Topup's Status API directly. Non-fatal per
     * order: one order's Status API call failing shouldn't stop the rest
     * of the batch from being checked.
     *
     * Deliberately uses only the ALREADY-EXISTING findByStatus() (no new
     * repository method or DB migration needed) -- filters by age in
     * memory instead of in the query, and gives up on an order after ~1
     * hour by checking createdAt rather than maintaining a separate
     * attempt-counter column. Good enough for now; if pending volume ever
     * gets large enough that scanning all PENDING_VERIFICATION rows in
     * memory becomes a real cost, that's the point to add a proper indexed
     * query + attempt-counter column.
     */
    @org.springframework.scheduling.annotation.Scheduled(fixedDelay = 300_000) // every 5 minutes
    suspend fun reconcilePendingRecharges() {
        val allPending = try {
            rechargeRepo.findByStatus("PENDING_VERIFICATION")
        } catch (e: Exception) {
            log.error("Reconciliation: failed to fetch pending orders", e)
            return
        }

        if (allPending.isEmpty()) return

        val now = Instant.now()
        val eligible = allPending.filter { order ->
            val ageSinceUpdate = Duration.between(order.updatedAt, now).seconds
            val ageSinceCreated = Duration.between(order.createdAt, now).toMinutes()
            // Give A1Topup at least 2 minutes to resolve naturally before we
            // start asking, and stop trying after ~1 hour -- a Pending that
            // hasn't resolved by then almost certainly needs a human, not
            // more polling.
            ageSinceUpdate >= 120 && ageSinceCreated < 60
        }

        if (eligible.isEmpty()) return
        log.info("Reconciliation: checking {} pending order(s)", eligible.size)

        for (order in eligible) {
            try {
                val result = a1topupClient.checkStatus(order.id.toString())
                if (result.needsStatusCheck) {
                    // Still genuinely pending / unresolved -- leave as-is,
                    // try again next cycle (updated_at won't change here,
                    // so it stays eligible next run too).
                    log.info("Reconciliation: orderId={} still pending", order.id)
                } else {
                    resolveA1TopupOutcome(order.id.toString(), result)
                }
            } catch (e: Exception) {
                log.warn("Reconciliation: status check failed for orderId={} (non-fatal, will retry next cycle)",
                    order.id, e)
            }
        }
    }

    /**
     * Shared resolution logic for both the callback and the poller --
     * updates order status, fires auto-refund on confirmed failure, and
     * credits the gold coin reward on confirmed success. Mirrors the
     * success/failure branches in handleWebhookCaptured() (same
     * razorpayClient.refund(paymentId, notes) call, same updateAfterConfirm
     * shape), applied to an order that was previously left in
     * PENDING_VERIFICATION.
     */
    private suspend fun resolveA1TopupOutcome(orderId: String, result: A1TopupRechargeResult) {
        val order = rechargeRepo.findById(java.util.UUID.fromString(orderId)) ?: run {
            log.warn("Reconciliation: no order found for orderId={}, ignoring", orderId)
            return
        }

        // Don't re-process an order that's already been finalized by
        // another path (e.g. the original webhook eventually resolved it
        // too, or this callback/poll fired twice) -- idempotency guard.
        if (order.status != "PENDING_VERIFICATION") {
            log.info("Reconciliation: orderId={} already resolved (status={}), skipping", orderId, order.status)
            return
        }

        if (result.success) {
            rechargeRepo.updateAfterConfirm(
                id = order.id!!,
                status = "RECHARGE_SUCCESS",
                razorpayPaymentId = order.razorpayPaymentId,
                a1topupStatus = "SUCCESS",
                a1topupRawResponse = toSafeJson(result.rawResponse),
                goldAutoInvest = false,
                goldTxnId = null
            )
            log.info("Reconciliation: orderId={} resolved SUCCESS", orderId)

            if (order.planValidityDays != null && order.planValidityDays > 0) {
                val expiryDate = LocalDate.now().plusDays(order.planValidityDays.toLong())
                rechargeRepo.setExpiryDate(order.id!!, expiryDate)
            }

            if (order.planAmount >= GOLD_ELIGIBLE_PLAN_AMOUNT) {
                try {
                    goldRewardService.creditRewardForRecharge(
                        userId = order.userId,
                        rechargeTxnId = order.id.toString(),
                        rechargeAmount = order.planAmount
                    )
                } catch (e: Exception) {
                    log.warn("Reconciliation: gold reward crediting failed (non-fatal): orderId={}", orderId, e)
                }
            }
        } else {
            // Same refund call/signature as handleWebhookCaptured()'s
            // confirmed-failure path -- razorpayClient.refund(paymentId,
            // notes), not (paymentId, amount, reason). Full refund of the
            // captured payment; A1Topup's own API doesn't support partial
            // recharge delivery so there's no partial-refund case here.
            var finalStatus = "RECHARGE_FAILED"
            var refundFailureNote: String? = null
            try {
                val refund = razorpayClient.refund(
                    paymentId = order.razorpayPaymentId!!,
                    notes = mapOf(
                        "reason" to "recharge_delivery_failed",
                        "rechargeOrderId" to order.id.toString(),
                        "resolvedVia" to "reconciliation"
                    )
                )
                finalStatus = "REFUNDED"
                log.info("Reconciliation: orderId={} auto-refunded: refundId={}", orderId, refund.id)
            } catch (e: Exception) {
                log.error(
                    "Reconciliation: REFUND FAILED for orderId={} -- customer still owed money, needs manual refund. Error: {}",
                    orderId, e.message, e
                )
                refundFailureNote = "Auto-refund failed: ${e.message}. Needs manual refund."
            }

            rechargeRepo.updateAfterConfirm(
                id = order.id!!,
                status = finalStatus,
                razorpayPaymentId = order.razorpayPaymentId,
                a1topupStatus = "FAILED",
                a1topupRawResponse = toSafeJson(result.rawResponse),
                goldAutoInvest = false,
                goldTxnId = null,
                failureReason = refundFailureNote
            )
        }
    }

}