package `in`.youpi.recharge.service

import `in`.youpi.core.Result
import `in`.youpi.core.WalletCreditPort
import `in`.youpi.core.WalletDebitOutcome
import `in`.youpi.core.WalletDebitPort
import `in`.youpi.core.maskMobile
import `in`.youpi.core.razorpay.RazorpayClient
import `in`.youpi.core.razorpay.RazorpayOrderCreationException
import `in`.youpi.core.razorpay.RazorpayRefundException
import `in`.youpi.events.PushNotificationService
import `in`.youpi.auth.repository.UserRepository
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
import java.time.ZoneId
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

    // REVERTED from CashfreeClient back to RazorpayClient (temporary
    // Cashfree wallet-support limitation). See doc comments below on
    // createOrder() and the refund calls for the concrete API differences
    // this swap requires -- it is NOT a drop-in rename.
    private val razorpayClient: RazorpayClient,
    private val a1topupClient: A1TopupClient,
    // ← NAYA: WALLET payment mode ke liye. Interfaces (shared/core) hain,
    // concrete WalletService nahi -- isse modules:recharge ko modules:wallet
    // pe compile-time depend nahi karna padta (recharge -> gold -> wallet
    // already exists, ek aur cycle risk avoid kiya).
    private val walletCreditPort: WalletCreditPort,   // ← refund/reversal jab wallet-paid recharge fail ho
    private val walletDebitPort: WalletDebitPort,      // ← debit jab user WALLET se pay kare
    // Push notification for the "app was fully closed by the time
    // fulfillment confirmed" case -- see PushNotificationService.kt's doc
    // comment for the full picture of why this exists alongside the
    // client-side sync/async polling.
    private val pushNotificationService: PushNotificationService,
    private val userRepository: UserRepository,
    @Value("\${mplan.api.key}") private val mplanApiKey: String,
    @Value("\${mplan.api.plans-url}") private val mplanPlansUrl: String,
    @Value("\${mplan.api.mobile-plans-url}") private val mplanMobilePlansUrl: String,
    @Value("\${mplan.api.operator-check-url}") private val mplanOperatorCheckUrl: String,
    @Value("\${youpi.recharge.gold-invest-percentage:1.0}") private val goldInvestPercentage: BigDecimal,
    // NAYA (for this revert): Razorpay's Flutter checkout SDK needs key_id
    // to open the checkout sheet -- Cashfree's flow instead needed a
    // payment_session_id returned from order-creation. RechargeOrderResponse
    // must expose razorpayKeyId now (see DTO note in createOrder() below).
    @Value("\${youpi.razorpay.key-id:}") private val razorpayKeyId: String,
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

        private val GOLD_ELIGIBLE_PLAN_AMOUNT = BigDecimal("249")

        private val MIN_DELIVERABLE_AMOUNT = BigDecimal("29")

        private val IST = ZoneId.of("Asia/Kolkata")
    }

    // ── Plan Fetching (Redis Cached) ── -- UNCHANGED, no gateway involvement below this point until createOrder()

    private val operatorCodeMap = mapOf(
        "VI" to 1,
        "AIRTEL" to 2,
        "MTNL" to 3,
        "BSNL" to 4,
        "JIO" to 5
    )

    private val circleCodeMap = mapOf(
        "ANDHRAPRADESH" to 2,
        "ASSAM" to 3,
        "BIHARJHARKHAND" to 4,
        "DELHINCR" to 5,
        "GUJARAT" to 6,
        "HIMACHALPRADESH" to 7,
        "HARYANA" to 8,
        "JAMMUKASHMIR" to 9,
        "KERALA" to 10,
        "KARNATAKA" to 11,
        "KOLKATA" to 12,
        "MAHARASHTRA" to 13,
        "MADHYAPRADESHCHHATTISGARH" to 14,
        "MUMBAI" to 15,
        "NORTHEAST" to 16,
        "ORISSA" to 17,
        "PUNJAB" to 18,
        "RAJASTHAN" to 19,
        "TAMILNADU" to 20,
        "UPEAST" to 21,
        "UPWEST" to 22,
        "WESTBENGAL" to 23,
        "CHENNAI" to 25
    )

    private fun normalizeKey(s: String): String =
        s.trim().uppercase().replace(Regex("[\\s_-]+"), "")

    suspend fun fetchPlans(operator: String, circle: String): Result<List<PlanResponse>, RechargeException> {
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
            val trimmedKey = mplanApiKey.trim()

            val uri = org.springframework.web.util.UriComponentsBuilder
                .fromHttpUrl(mplanMobilePlansUrl)
                .queryParam("apikey", trimmedKey)
                .queryParam("operator_code", operatorCode)
                .queryParam("circle_code", circleCode)
                .build()
                .encode()
                .toUri()

            val response = webClient.get()
                .uri(uri)
                .retrieve()
                .bodyToMono(String::class.java)
                .awaitSingle()

            val root = objectMapper.readTree(response)

            if (root.path("status").asInt(0) != 1) {
                val errorMsg = root.path("records").path("msg").asText("Unknown mPlan API error")
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

    // ── Server-side plan/price resolution (SECURITY FIX) ──
    //
    // req.planAmount and req.planValidityDays are client-supplied and MUST
    // NEVER be trusted directly for anything that moves money or triggers
    // A1Topup delivery -- a tampered planAmount would previously flow
    // straight into both the Razorpay charge amount and the A1Topup
    // delivery amount unchanged. This re-resolves the authoritative plan
    // (amount + validity) from the same cached/mPlan catalog the user
    // browsed, keyed by planId, and that catalog value is what's actually
    // used everywhere downstream. If the client-sent planAmount disagrees
    // with the catalog (tampering, or a genuine price change mid-session),
    // the order is rejected rather than silently charged at the
    // authoritative amount -- the user should see and confirm the real
    // price, not be charged something other than what was on screen.
    //
    // planId is ephemeral (regenerated on every cache refill, see
    // fetchPlansFromApi above) so this naturally also rejects stale
    // planIds from an expired 30-min plan cache -- caller should refresh
    // /v1/recharge/plans and retry, which is the correct UX anyway since
    // the price may genuinely have changed.
    private suspend fun resolveAuthoritativePlan(
        userId: UUID,
        req: CreateRechargeRequest
    ): Result<PlanResponse, RechargeException> {
        val circle = req.circle
            ?: return Result.failure(RechargeApiException("Circle is required to resolve plan pricing."))

        val plansResult = fetchPlans(req.operator, circle)
        val plans = when (plansResult) {
            is Result.Success -> plansResult.value
            is Result.Failure -> return Result.failure(plansResult.error)
        }

        val verifiedPlan = plans.find { it.planId == req.planId }
            ?: run {
                log.warn(
                    "Recharge order rejected: planId={} not found in current catalog for operator={}, circle={}, userId={} " +
                            "(client-supplied amount={}) -- stale/expired plan cache or tampered planId",
                    req.planId, req.operator, req.circle, userId, req.planAmount
                )
                return Result.failure(PlanNotFoundException())
            }

        if (verifiedPlan.amount.compareTo(req.planAmount) != 0) {
            // Reject rather than silently charge the authoritative amount --
            // either the client sent a tampered value, or the plan cache
            // refreshed with a genuinely changed price between the user
            // viewing plans and confirming. Either way, silently charging
            // something other than what the user saw on screen is bad
            // practice even though the server-resolved amount itself is
            // safe. Cleaner to force a refresh + retry.
            log.warn(
                "SECURITY: recharge planAmount mismatch -- userId={}, planId={}, clientSentAmount={}, " +
                        "authoritativeAmount={}. Rejecting order.",
                userId, req.planId, req.planAmount, verifiedPlan.amount
            )
            return Result.failure(RechargePlanPriceMismatchException())
        }

        return Result.success(verifiedPlan)
    }

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
                log.error("mPlan operator-check failed for mobile={}: msg={}, fullResponse={}",
                    maskMobile(mobileNumber), errorMsg, response)
                return Result.failure(OperatorDetectionException(errorMsg))
            }

            val operator = normalizeKey(records.path("Operator").asText(""))
            val circle = normalizeKey(records.path("circle").asText(""))

            if (operator !in operatorCodeMap || circle !in circleCodeMap) {
                log.error(
                    "mPlan operator-check returned unmapped operator/circle: operator={}, circle={}, mobile={}",
                    operator, circle, maskMobile(mobileNumber)
                )
                return Result.failure(OperatorDetectionException(
                    "Detected operator/circle not recognized: $operator / $circle"
                ))
            }

            log.info("Operator detected: mobile={}, operator={}, circle={}", maskMobile(mobileNumber), operator, circle)
            Result.success(OperatorDetectionResponse(operator = operator, circle = circle))
        } catch (e: Exception) {
            log.error("mPlan operator-check call failed for mobile={}", maskMobile(mobileNumber), e)
            Result.failure(OperatorDetectionException("Failed to detect operator: ${e.message}"))
        }
    }

    // ── Order Creation ──
    //
    // REVERTED to RazorpayClient. Three concrete differences from the
    // Cashfree version this replaces:
    //   1. Amount unit: Razorpay wants PAISE (Long), Cashfree wanted
    //      RUPEES (Double) -- amountPaise computed once, reused.
    //   2. No customerPhone needed at order-creation (Cashfree required it,
    //      Razorpay doesn't) -- req.mobileNumber no longer passed here.
    //   3. No payment_session_id concept -- Razorpay's Flutter checkout SDK
    //      instead needs the account's key_id to open the checkout sheet.
    //      RechargeOrderResponse must carry razorpayKeyId now (added
    //      alongside the now-always-null paymentSessionId field so nothing
    //      else that reads that DTO breaks -- confirm RechargeOrderResponse
    //      actually has a razorpayKeyId field; add one if it doesn't yet).
    suspend fun createOrder(userId: UUID, req: CreateRechargeRequest): Result<RechargeOrderResponse, RechargeException> {
        if (req.paymentMode == PaymentMode.WALLET) {
            return createWalletPaidOrder(userId, req)
        }

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

        // SECURITY: never trust req.planAmount / req.planValidityDays directly --
        // resolve the authoritative plan server-side from the same catalog the
        // user browsed, keyed by planId. See resolveAuthoritativePlan() above.
        val verifiedPlan = when (val planResult = resolveAuthoritativePlan(userId, req)) {
            is Result.Success -> planResult.value
            is Result.Failure -> return Result.failure(planResult.error)
        }
        val planAmount = verifiedPlan.amount
        // No client fallback here either -- a malformed/empty validity in
        // the catalog is a data problem to surface and fix, not something
        // to silently paper over with a client-supplied number.
        val planValidityDays = verifiedPlan.validity.toIntOrNull()
            ?: return Result.failure(RechargeApiException("Invalid plan validity in catalog"))

        val emiMonths: Short? = when (req.paymentMode) {
            PaymentMode.EMI_3  -> 3
            PaymentMode.EMI_6  -> 6
            PaymentMode.EMI_12 -> 12
            else -> null
        }
        val emiAmount = emiMonths?.let {
            planAmount.divide(BigDecimal(it.toInt()), 2, java.math.RoundingMode.CEILING)
        }

        // Call Razorpay BEFORE writing anything to the DB -- same reasoning
        // as before: a real API failure here must not leave an orphaned
        // "INITIATED" order with no way to actually pay it.
        val amountPaise = planAmount.multiply(BigDecimal(100)).toLong()
        val razorpayOrderId = try {
            razorpayClient.createOrder(
                amountPaise = amountPaise,
                receipt = req.idempotencyKey,
                notes = mapOf(
                    "purpose" to "RECHARGE",
                    "userId" to userId.toString(),
                    "mobileNumber" to req.mobileNumber
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
            planAmount = planAmount,
            planDetails = "{}",
            paymentMode = req.paymentMode.name,
            emiMonths = emiMonths,
            emiAmount = emiAmount,
            status = "INITIATED",
            razorpayOrderId = razorpayOrderId,
            goldAutoInvest = false,
            idempotencyKey = req.idempotencyKey,
            planValidityDays = planValidityDays
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
            order.id, planAmount, req.paymentMode, razorpayOrderId)

        return Result.success(
            RechargeOrderResponse(
                orderId = order.id!!,
                razorpayOrderId = razorpayOrderId,
                paymentSessionId = null,        // no longer applicable -- Cashfree-only concept
                razorpayKeyId = razorpayKeyId,  // NEW -- Flutter checkout SDK needs this to open Razorpay checkout
                amount = planAmount,
                status = "INITIATED",
                paymentMode = req.paymentMode.name
            )
        )
    }

    // ── WALLET-Paid Recharge (synchronous, no gateway/webhook) ── -- UNCHANGED, no gateway involvement
    private suspend fun createWalletPaidOrder(userId: UUID, req: CreateRechargeRequest): Result<RechargeOrderResponse, RechargeException> {
        val existing = rechargeRepo.findByIdempotencyKey(req.idempotencyKey)
        if (existing != null) {
            return Result.success(
                RechargeOrderResponse(
                    orderId = existing.id!!,
                    razorpayOrderId = existing.razorpayOrderId,
                    paymentSessionId = null,
                    amount = existing.planAmount,
                    status = existing.status,
                    paymentMode = existing.paymentMode
                )
            )
        }

        // SECURITY: same authoritative-price resolution as the gateway-paid
        // path above -- a tampered planAmount here would otherwise debit
        // the wallet for less than the real plan cost.
        val verifiedPlan = when (val planResult = resolveAuthoritativePlan(userId, req)) {
            is Result.Success -> planResult.value
            is Result.Failure -> return Result.failure(planResult.error)
        }
        val planAmount = verifiedPlan.amount
        val planValidityDays = verifiedPlan.validity.toIntOrNull()
            ?: return Result.failure(RechargeApiException("Invalid plan validity in catalog"))

        val debitOutcome = walletDebitPort.debitForService(
            userId = userId,
            walletType = "NBFC",
            amount = planAmount,
            serviceCode = "RECHARGE",
            referenceId = null,
            description = "Recharge ${req.mobileNumber} (₹${planAmount})",
            idempotencyKey = "recharge_debit_${req.idempotencyKey}"
        )

        when (debitOutcome) {
            is WalletDebitOutcome.Rejected -> {
                log.warn("WALLET-paid recharge rejected at debit: userId={}, reason={}, message={}",
                    userId, debitOutcome.reason, debitOutcome.message)
                return Result.failure(WalletPaymentRejectedException(debitOutcome.message))
            }
            is WalletDebitOutcome.Success -> { /* proceed */ }
        }

        val order = rechargeRepo.insertOrder(
            userId = userId,
            mobileNumber = req.mobileNumber,
            operator = req.operator,
            circle = req.circle,
            planId = req.planId,
            planAmount = planAmount,
            planDetails = "{}",
            paymentMode = req.paymentMode.name,
            emiMonths = null,
            emiAmount = null,
            status = "INITIATED",
            razorpayOrderId = null,
            goldAutoInvest = false,
            idempotencyKey = req.idempotencyKey,
            planValidityDays = planValidityDays
        )

        log.info("Recharge order created (WALLET paid): orderId={}, amount=₹{}, userId={}", order.id, planAmount, userId)

        deliverAndResolve(order, paymentIdentifier = "WALLET-${order.id}")

        val finalOrder = rechargeRepo.findById(order.id!!) ?: order
        return Result.success(
            RechargeOrderResponse(
                orderId = finalOrder.id!!,
                razorpayOrderId = null,
                paymentSessionId = null,
                amount = finalOrder.planAmount,
                status = finalOrder.status,
                paymentMode = finalOrder.paymentMode
            )
        )
    }

    // ── Webhook-Driven Completion ── -- UNCHANGED logic; still called from
    // PaymentService's Razorpay webhook handler once it verifies the
    // request and finds a recharge order for the razorpay_order_id.
    suspend fun handleWebhookCaptured(razorpayOrderId: String, razorpayPaymentId: String): Boolean {
        val order = rechargeRepo.findByRazorpayOrderId(razorpayOrderId) ?: run {
            log.debug("Recharge webhook: no recharge order for razorpayOrderId={} (likely a different purpose)", razorpayOrderId)
            return false
        }

        if (order.status != "INITIATED") {
            log.info("Recharge webhook: order already processed (status={}), skipping orderId={}", order.status, order.id)
            return true
        }

        return deliverAndResolve(order, razorpayPaymentId)
    }

    // ── Shared delivery + outcome + refund + reward + push logic ──
    //
    // REFUND CHANGE (the important one): Razorpay refunds are issued
    // against a PAYMENT id, not an order id -- unlike Cashfree, which
    // refunded against orderId. `paymentIdentifier` (the param this
    // function already receives) IS the razorpay_payment_id for a
    // gateway-paid order, captured from the webhook -- so the refund call
    // below uses that, not order.razorpayOrderId. For WALLET-paid orders,
    // paymentIdentifier is a synthetic "WALLET-{orderId}" marker and that
    // branch never calls the gateway at all (wallet reversal instead),
    // same as before.
    private suspend fun deliverAndResolve(order: RechargeOrderEntity, paymentIdentifier: String): Boolean {
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
            log.error("A1Topup: recharge call threw for orderId={} -- treating as failure for refund purposes (UNCONFIRMED, see comment)", order.id, e)
            status = "RECHARGE_FAILED"
            a1topupStatus = "FAILED"
            a1topupRawResponse = "error: ${e.message}"
        }

        var refundFailureNote: String? = null
        if (status == "RECHARGE_FAILED") {
            if (order.paymentMode == "WALLET") {
                try {
                    val reversed = walletCreditPort.reverseDebit(
                        userId = order.userId,
                        walletType = "NBFC",
                        amountPaise = order.planAmount.multiply(BigDecimal(100)).toLong(),
                        referenceType = "RECHARGE_REFUND",
                        referenceId = order.id,
                        description = "Refund: recharge delivery failed (orderId=${order.id})",
                        idempotencyKey = "recharge_refund_${order.id}"
                    )
                    if (reversed) {
                        status = "REFUNDED"
                        log.info("Wallet reversal credited for orderId={} after A1Topup failure", order.id)
                    } else {
                        log.error(
                            "WALLET REVERSAL FAILED for orderId={} -- customer still owed money, " +
                                    "needs manual wallet credit.", order.id
                        )
                        refundFailureNote = "Auto wallet-reversal failed. Needs manual credit."
                    }
                } catch (e: Exception) {
                    log.error(
                        "WALLET REVERSAL FAILED for orderId={} -- customer still owed money, " +
                                "needs manual wallet credit. Error: {}", order.id, e.message, e
                    )
                    refundFailureNote = "Auto wallet-reversal failed: ${e.message}. Needs manual credit."
                }
            } else {
                try {
                    // paymentIdentifier here IS the razorpay_payment_id (see
                    // doc comment above the function) -- Razorpay refunds
                    // against payment id, never order id.
                    val refund = razorpayClient.refund(
                        paymentId = paymentIdentifier,
                        amountPaise = order.planAmount.multiply(BigDecimal(100)).toLong(),
                        notes = mapOf("reason" to "recharge_delivery_failed", "orderId" to order.id.toString())
                    )
                    status = "REFUNDED"
                    log.info(
                        "Razorpay refund issued for orderId={} after A1Topup failure: refundId={}, status={}",
                        order.id, refund.id, refund.status
                    )
                } catch (e: RazorpayRefundException) {
                    log.error(
                        "REFUND FAILED for orderId={} after A1Topup failure -- customer still owed money, " +
                                "needs manual refund via Razorpay dashboard. Error: {}",
                        order.id, e.message, e
                    )
                    refundFailureNote = "Auto-refund failed: ${e.message}. Needs manual refund."
                } catch (e: Exception) {
                    log.error(
                        "REFUND FAILED for orderId={} after A1Topup failure -- customer still owed money, " +
                                "needs manual refund via Razorpay dashboard. Error: {}",
                        order.id, e.message, e
                    )
                    refundFailureNote = "Auto-refund failed: ${e.message}. Needs manual refund."
                }
            }
        }

        var updatedOrder = rechargeRepo.updateAfterConfirm(
            id = order.id!!,
            status = status,
            razorpayPaymentId = paymentIdentifier,
            a1topupStatus = a1topupStatus,
            a1topupRawResponse = toSafeJson(a1topupRawResponse),
            goldAutoInvest = order.goldAutoInvest,
            goldTxnId = order.goldTxnId,
            failureReason = refundFailureNote
        )

        log.info("Recharge confirmed: orderId={}, amount={}, paymentMode={}", updatedOrder.id, updatedOrder.planAmount, order.paymentMode)

        if (updatedOrder.status == "RECHARGE_SUCCESS" && order.planValidityDays != null && order.planValidityDays > 0) {
            val expiryDate = LocalDate.now(IST).plusDays(order.planValidityDays.toLong())
            rechargeRepo.setExpiryDate(updatedOrder.id!!, expiryDate)
            log.info("Recharge expiry set: orderId={}, expiryDate={}", updatedOrder.id, expiryDate)
        }

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

            try {
                sendRechargeSuccessPushIfEligible(order.userId, updatedOrder.id.toString(), updatedOrder.planAmount)
            } catch (e: Exception) {
                log.warn("Push notification dispatch failed (non-fatal): orderId={}, reason={}",
                    updatedOrder.id, e.message)
            }
        }

        return true
    }

    private suspend fun sendRechargeSuccessPushIfEligible(userId: UUID, orderId: String, planAmount: BigDecimal) {
        if (planAmount < GoldRewardService.MIN_RECHARGE_FOR_REWARD) return

        val earnedValueRupees = planAmount
            .multiply(GoldRewardService.REWARD_PERCENTAGE)
            .setScale(2, java.math.RoundingMode.HALF_UP)
        val earnedCoins = earnedValueRupees
            .divide(GoldRewardService.COIN_VALUE_RUPEES, 0, java.math.RoundingMode.HALF_UP)
            .toInt()
            .coerceAtLeast(0)

        val user = userRepository.findById(userId) ?: return
        pushNotificationService.sendRechargeSuccessPush(
            fcmToken = user.fcmToken,
            orderId = orderId,
            amountRupees = planAmount,
            earnedCoins = earnedCoins,
            earnedValueRupees = earnedValueRupees
        )
    }

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

    suspend fun getActiveRecharge(userId: UUID): ActiveRechargeResponse? {
        val order = rechargeRepo.findActiveRecharge(userId) ?: return null
        val expiryDate = order.expiryDate ?: return null

        return ActiveRechargeResponse(
            orderId = order.id!!,
            mobileNumber = order.mobileNumber,
            operator = order.operator,
            planAmount = order.planAmount,
            expiryDate = expiryDate,
            daysRemaining = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.now(IST), expiryDate).coerceAtLeast(0)
        )
    }

    suspend fun getActiveRecharges(userId: UUID): List<ActiveRechargeResponse> {
        return rechargeRepo.findActiveRecharges(userId).mapNotNull { order ->
            val expiryDate = order.expiryDate ?: return@mapNotNull null
            ActiveRechargeResponse(
                orderId = order.id!!,
                mobileNumber = order.mobileNumber,
                operator = order.operator,
                planAmount = order.planAmount,
                expiryDate = expiryDate,
                daysRemaining = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.now(IST), expiryDate).coerceAtLeast(0)
            )
        }
    }

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

    private fun toSafeJson(raw: String): String {
        return try {
            objectMapper.readTree(raw)
            raw
        } catch (e: Exception) {
            objectMapper.writeValueAsString(mapOf("raw" to raw))
        }
    }

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
            ageSinceUpdate >= 120 && ageSinceCreated < 60
        }

        if (eligible.isEmpty()) return
        log.info("Reconciliation: checking {} pending order(s)", eligible.size)

        for (order in eligible) {
            try {
                val result = a1topupClient.checkStatus(order.id.toString())
                if (result.needsStatusCheck) {
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

    // Mirrors deliverAndResolve()'s refund logic: refund against
    // order.razorpayPaymentId (the captured payment id, already stored on
    // the order by the time it reached PENDING_VERIFICATION), NOT
    // order.razorpayOrderId.
    private suspend fun resolveA1TopupOutcome(orderId: String, result: A1TopupRechargeResult) {
        val order = rechargeRepo.findById(java.util.UUID.fromString(orderId)) ?: run {
            log.warn("Reconciliation: no order found for orderId={}, ignoring", orderId)
            return
        }

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
                val expiryDate = LocalDate.now(IST).plusDays(order.planValidityDays.toLong())
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

            try {
                sendRechargeSuccessPushIfEligible(order.userId, order.id.toString(), order.planAmount)
            } catch (e: Exception) {
                log.warn("Reconciliation: push notification dispatch failed (non-fatal): orderId={}", orderId, e)
            }
        } else {
            var finalStatus = "RECHARGE_FAILED"
            var refundFailureNote: String? = null
            try {
                // Refund against the PAYMENT id (order.razorpayPaymentId,
                // already populated when the webhook first moved this
                // order to PENDING_VERIFICATION) -- not the order id.
                val refund = razorpayClient.refund(
                    paymentId = order.razorpayPaymentId ?: "",
                    amountPaise = order.planAmount.multiply(BigDecimal(100)).toLong(),
                    notes = mapOf("reason" to "recharge_delivery_failed_reconciliation", "orderId" to order.id.toString())
                )
                finalStatus = "REFUNDED"
                log.info("Reconciliation: orderId={} Razorpay auto-refunded: refundId={}", orderId, refund.id)
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