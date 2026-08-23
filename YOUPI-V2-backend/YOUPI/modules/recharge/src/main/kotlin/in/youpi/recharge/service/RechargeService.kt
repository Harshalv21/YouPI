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
    @Qualifier("proxiedWebClient") private val webClient: WebClient,
    private val investService: InvestService,
    private val goldRewardService: GoldRewardService,
    private val razorpayClient: RazorpayClient,
    private val a1topupClient: A1TopupClient,
    private val walletCreditPort: WalletCreditPort,
    private val walletDebitPort: WalletDebitPort,
    private val pushNotificationService: PushNotificationService,
    private val userRepository: UserRepository,
    @Value("\${mplan.api.key}") private val mplanApiKey: String,
    @Value("\${mplan.api.plans-url}") private val mplanPlansUrl: String,
    @Value("\${mplan.api.mobile-plans-url}") private val mplanMobilePlansUrl: String,
    @Value("\${mplan.api.operator-check-url}") private val mplanOperatorCheckUrl: String,
    @Value("\${youpi.recharge.gold-invest-percentage:1.0}") private val goldInvestPercentage: BigDecimal,
    @Value("\${youpi.razorpay.key-id:}") private val razorpayKeyId: String,
    @Value("\${youpi.recharge.mock-enabled:false}") private val mockEnabled: Boolean
) {
    private val log = LoggerFactory.getLogger(javaClass)

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

        // NEW -- Razorpay's practical minimum chargeable amount. If the
        // gateway-portion of a SPLIT payment would be smaller than this,
        // reject the split upfront rather than let Razorpay order creation
        // fail downstream (after we've already debited the wallet).
        private val MIN_GATEWAY_CHARGE_AMOUNT = BigDecimal("1.00")

        // NEW -- how long a SPLIT order can sit in INITIATED (wallet
        // debited, gateway checkout not yet completed) before the
        // reconciliation job treats it as abandoned and releases the
        // wallet hold. Generous enough to not race a slow-but-genuine
        // checkout, short enough that money doesn't stay "stuck" for long.
        private val SPLIT_ABANDON_THRESHOLD_MINUTES = 30L
    }

    private val operatorCodeMap = mapOf(
        "VI" to 1, "AIRTEL" to 2, "MTNL" to 3, "BSNL" to 4, "JIO" to 5
    )

    private val circleCodeMap = mapOf(
        "ANDHRAPRADESH" to 2, "ASSAM" to 3, "BIHARJHARKHAND" to 4, "DELHINCR" to 5,
        "GUJARAT" to 6, "HIMACHALPRADESH" to 7, "HARYANA" to 8, "JAMMUKASHMIR" to 9,
        "KERALA" to 10, "KARNATAKA" to 11, "KOLKATA" to 12, "MAHARASHTRA" to 13,
        "MADHYAPRADESHCHHATTISGARH" to 14, "MUMBAI" to 15, "NORTHEAST" to 16,
        "ORISSA" to 17, "PUNJAB" to 18, "RAJASTHAN" to 19, "TAMILNADU" to 20,
        "UPEAST" to 21, "UPWEST" to 22, "WESTBENGAL" to 23, "CHENNAI" to 25
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
        operator: String, circle: String, cacheKey: String
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
                .build().encode().toUri()

            val response = webClient.get().uri(uri).retrieve()
                .bodyToMono(String::class.java).awaitSingle()

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
                            operator = operator, circle = circle,
                            amount = BigDecimal(plan.path("rs").asText("0")),
                            validity = plan.path("validity").asText(""),
                            description = plan.path("desc").asText(""),
                            category = category.uppercase(),
                            data = null, talktime = null, sms = null
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

    private suspend fun resolveAuthoritativePlan(
        userId: UUID, req: CreateRechargeRequest
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
                .build().encode().toUri()

            val response = webClient.get().uri(uri).retrieve()
                .bodyToMono(String::class.java).awaitSingle()

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

    // ── Order Creation ── -- NOW routes to THREE modes: WALLET (full),
    // SPLIT (wallet + gateway, NEW), or gateway-only (Razorpay, existing).
    suspend fun createOrder(userId: UUID, req: CreateRechargeRequest): Result<RechargeOrderResponse, RechargeException> {
        if (req.paymentMode == PaymentMode.WALLET) {
            return createWalletPaidOrder(userId, req)
        }
        if (req.paymentMode == PaymentMode.SPLIT) {
            return createSplitPaymentOrder(userId, req)
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

        val verifiedPlan = when (val planResult = resolveAuthoritativePlan(userId, req)) {
            is Result.Success -> planResult.value
            is Result.Failure -> return Result.failure(planResult.error)
        }
        val planAmount = verifiedPlan.amount
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
                paymentSessionId = null,
                razorpayKeyId = razorpayKeyId,
                amount = planAmount,
                status = "INITIATED",
                paymentMode = req.paymentMode.name
            )
        )
    }

    // ── WALLET-Paid Recharge (synchronous, no gateway/webhook) ── -- UNCHANGED
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
                return Result.failure(
                    WalletPaymentRejectedException(
                        reason = debitOutcome.message,
                        available = debitOutcome.available,
                        required = debitOutcome.required
                    )
                )
            }
            is WalletDebitOutcome.Success -> { /* proceed */ }
        }

        // Wallet debit above already succeeded. If this insert fails for any
        // reason (constraint violation, DB error, etc.), the wallet must be
        // reversed here -- otherwise the user is left debited with no
        // recharge_orders row at all, which reconcileStuckSplitOrders() and
        // every other recovery job can never find (they all query
        // recharge_orders). See Aug 21 incident: chk_payment_mode constraint
        // rejected payment_mode='WALLET'/'SPLIT', wallet stayed debited with
        // no order row, required manual DB reversal.
        val order = try {
            rechargeRepo.insertOrder(
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
        } catch (e: Exception) {
            log.error(
                "WALLET-paid recharge: insertOrder FAILED after wallet debit -- reversing. userId={}, amount=₹{}, error={}",
                userId, planAmount, e.message, e
            )
            val reversed = walletCreditPort.reverseDebit(
                userId = userId,
                walletType = "NBFC",
                amountPaise = planAmount.multiply(BigDecimal(100)).toLong(),
                referenceType = "RECHARGE",
                referenceId = null,
                description = "Reversal: recharge order could not be created (wallet-paid, ${req.mobileNumber})",
                idempotencyKey = "recharge_wallet_insert_failure_reversal_${req.idempotencyKey}"
            )
            if (!reversed) {
                log.error(
                    "CRITICAL: WALLET-paid recharge wallet reversal FAILED after insertOrder failure -- " +
                            "userId={}, amount=₹{}, idempotencyKey={} -- needs manual wallet credit.",
                    userId, planAmount, req.idempotencyKey
                )
            }
            return Result.failure(RechargeApiException(e.message ?: "Could not create recharge order"))
        }

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

    // ── SPLIT-Paid Recharge (NEW) ──
    //
    // User pays PART of the plan amount from Wallet and the REMAINDER via
    // Razorpay (UPI/card/etc). Order of operations is deliberate:
    //
    //   1. Debit the wallet portion FIRST (same-DB, atomic, instantly
    //      reversible via walletCreditPort.reverseDebit() -- the exact
    //      mechanism deliverAndResolve() already uses for WALLET-mode
    //      refunds). This is a same-request operation with no external
    //      dependency, so it's safe to do first and cheap to undo.
    //   2. THEN create the Razorpay order for the remaining amount only.
    //      If this external call fails, the wallet debit from step 1 is
    //      immediately reversed inline, in the SAME request -- the user
    //      just sees a clean failure, no stuck state, no orphaned Razorpay
    //      order.
    //   3. The Flutter Razorpay checkout SDK must open for `gatewayAmount`
    //      (NOT the full plan amount) -- see RechargeOrderResponse fields.
    //
    // What this does NOT solve by itself: if the wallet debit succeeds,
    // the Razorpay order is created, but the USER ABANDONS the checkout
    // (closes the app, no webhook ever fires) -- wallet money would stay
    // debited with no resolution. That case is handled separately by
    // reconcileStuckSplitOrders() below (scheduled job).
    private suspend fun createSplitPaymentOrder(userId: UUID, req: CreateRechargeRequest): Result<RechargeOrderResponse, RechargeException> {
        val existing = rechargeRepo.findByIdempotencyKey(req.idempotencyKey)
        if (existing != null) {
            return Result.success(
                RechargeOrderResponse(
                    orderId = existing.id!!,
                    razorpayOrderId = existing.razorpayOrderId,
                    paymentSessionId = null,
                    razorpayKeyId = razorpayKeyId,
                    amount = existing.gatewayAmount ?: existing.planAmount,
                    walletAmount = existing.walletAmount,
                    gatewayAmount = existing.gatewayAmount,
                    status = existing.status,
                    paymentMode = existing.paymentMode
                )
            )
        }

        val verifiedPlan = when (val planResult = resolveAuthoritativePlan(userId, req)) {
            is Result.Success -> planResult.value
            is Result.Failure -> return Result.failure(planResult.error)
        }
        val planAmount = verifiedPlan.amount
        val planValidityDays = verifiedPlan.validity.toIntOrNull()
            ?: return Result.failure(RechargeApiException("Invalid plan validity in catalog"))

        // walletAmount is the user's CONSENTED wallet-portion, chosen and
        // confirmed on the split-payment consent screen client-side. It is
        // still re-validated server-side against the live wallet balance
        // inside debitForService() below -- never trust this number alone.
        val walletAmount = req.walletAmount
            ?: return Result.failure(RechargeApiException("walletAmount is required for SPLIT payment mode"))

        if (walletAmount <= BigDecimal.ZERO || walletAmount >= planAmount) {
            return Result.failure(RechargeApiException(
                "walletAmount must be greater than 0 and less than the plan amount for SPLIT mode " +
                        "(use WALLET mode for full-wallet payment, or omit paymentMode=SPLIT for full-gateway payment)"
            ))
        }

        val gatewayAmount = planAmount.subtract(walletAmount)
        if (gatewayAmount < MIN_GATEWAY_CHARGE_AMOUNT) {
            return Result.failure(RechargeApiException(
                "Remaining gateway amount (₹$gatewayAmount) is below the minimum chargeable amount. " +
                        "Reduce the wallet portion or pay fully from Wallet instead."
            ))
        }

        // STEP 1: debit wallet portion first.
        val debitOutcome = walletDebitPort.debitForService(
            userId = userId,
            walletType = "NBFC",
            amount = walletAmount,
            serviceCode = "RECHARGE",
            referenceId = null,
            description = "Split recharge ${req.mobileNumber} (wallet portion ₹$walletAmount of ₹$planAmount)",
            idempotencyKey = "recharge_split_wallet_debit_${req.idempotencyKey}"
        )

        when (debitOutcome) {
            is WalletDebitOutcome.Rejected -> {
                log.warn("SPLIT recharge rejected at wallet-debit step: userId={}, reason={}, message={}",
                    userId, debitOutcome.reason, debitOutcome.message)
                return Result.failure(
                    WalletPaymentRejectedException(
                        reason = debitOutcome.message,
                        available = debitOutcome.available,
                        required = debitOutcome.required
                    )
                )
            }
            is WalletDebitOutcome.Success -> { /* proceed to Razorpay */ }
        }

        // STEP 2: create Razorpay order for the REMAINDER only.
        val amountPaise = gatewayAmount.multiply(BigDecimal(100)).toLong()
        val razorpayOrderId = try {
            razorpayClient.createOrder(
                amountPaise = amountPaise,
                receipt = req.idempotencyKey,
                notes = mapOf(
                    "purpose" to "RECHARGE_SPLIT",
                    "userId" to userId.toString(),
                    "mobileNumber" to req.mobileNumber,
                    "planAmount" to planAmount.toString(),
                    "walletPortion" to walletAmount.toString()
                )
            ).id
        } catch (e: RazorpayOrderCreationException) {
            log.error("SPLIT recharge: Razorpay order creation failed for userId={}, reversing wallet debit of ₹{}",
                userId, walletAmount)

            val reversed = try {
                walletCreditPort.reverseDebit(
                    userId = userId,
                    walletType = "NBFC",
                    amountPaise = walletAmount.multiply(BigDecimal(100)).toLong(),
                    referenceType = "RECHARGE_SPLIT_REVERSAL",
                    referenceId = null,
                    description = "Reversal: gateway order creation failed for split recharge",
                    idempotencyKey = "recharge_split_wallet_reversal_${req.idempotencyKey}"
                )
            } catch (reverseEx: Exception) {
                log.error("Wallet reversal threw during SPLIT order-creation failure handling, userId={}", userId, reverseEx)
                false
            }

            if (!reversed) {
                // This is the one bad outcome of this design -- flag loudly
                // for manual ops follow-up, same severity as the existing
                // "WALLET REVERSAL FAILED" cases elsewhere in this file.
                log.error(
                    "CRITICAL: SPLIT recharge wallet reversal FAILED after Razorpay order-creation failure -- " +
                            "userId={}, amount=₹{}, idempotencyKey={} -- needs manual wallet credit.",
                    userId, walletAmount, req.idempotencyKey
                )
            }

            return Result.failure(RechargeApiException(e.message ?: "Razorpay order creation failed"))
        }

        // Wallet debit AND Razorpay order are both live at this point. If
        // this insert fails (constraint violation, DB error, etc.), the
        // wallet must be reversed here -- otherwise the user is left debited
        // with no recharge_orders row at all, which reconcileStuckSplitOrders()
        // can never find (it only scans existing recharge_orders rows). The
        // Razorpay order itself is left to expire unused -- Razorpay has no
        // cancel-order API, and it's harmless since nothing references it.
        // See Aug 21 incident: chk_payment_mode constraint rejected
        // payment_mode='SPLIT', wallet stayed debited with no order row,
        // required manual DB reversal.
        val order = try {
            rechargeRepo.insertOrder(
                userId = userId,
                mobileNumber = req.mobileNumber,
                operator = req.operator,
                circle = req.circle,
                planId = req.planId,
                planAmount = planAmount,
                planDetails = "{}",
                paymentMode = "SPLIT",
                emiMonths = null,
                emiAmount = null,
                status = "INITIATED",
                razorpayOrderId = razorpayOrderId,
                goldAutoInvest = false,
                idempotencyKey = req.idempotencyKey,
                planValidityDays = planValidityDays,
                walletAmount = walletAmount,      // NEW param -- see repository/migration notes
                gatewayAmount = gatewayAmount      // NEW param -- see repository/migration notes
            )
        } catch (e: Exception) {
            log.error(
                "SPLIT recharge: insertOrder FAILED after wallet debit + Razorpay order creation -- reversing wallet. " +
                        "userId={}, walletAmount=₹{}, razorpayOrderId={}, error={}",
                userId, walletAmount, razorpayOrderId, e.message, e
            )
            val reversed = walletCreditPort.reverseDebit(
                userId = userId,
                walletType = "NBFC",
                amountPaise = walletAmount.multiply(BigDecimal(100)).toLong(),
                referenceType = "RECHARGE",
                referenceId = null,
                description = "Reversal: split recharge order could not be created (${req.mobileNumber})",
                idempotencyKey = "recharge_split_insert_failure_reversal_${req.idempotencyKey}"
            )
            if (!reversed) {
                log.error(
                    "CRITICAL: SPLIT recharge wallet reversal FAILED after insertOrder failure -- " +
                            "userId={}, amount=₹{}, idempotencyKey={} -- needs manual wallet credit.",
                    userId, walletAmount, req.idempotencyKey
                )
            }
            return Result.failure(RechargeApiException(e.message ?: "Could not create recharge order"))
        }

        log.info(
            "SPLIT recharge order created: orderId={}, planAmount={}, walletPortion={}, gatewayPortion={}, razorpayOrderId={}",
            order.id, planAmount, walletAmount, gatewayAmount, razorpayOrderId
        )

        return Result.success(
            RechargeOrderResponse(
                orderId = order.id!!,
                razorpayOrderId = razorpayOrderId,
                paymentSessionId = null,
                razorpayKeyId = razorpayKeyId,
                // IMPORTANT: `amount` here is the GATEWAY-CHARGE amount --
                // the Flutter Razorpay checkout SDK must open for THIS
                // number, not planAmount. walletAmount/gatewayAmount are
                // also returned explicitly so the UI can show a clear
                // breakdown without re-deriving it.
                amount = gatewayAmount,
                walletAmount = walletAmount,
                gatewayAmount = gatewayAmount,
                status = "INITIATED",
                paymentMode = "SPLIT"
            )
        )
    }

    // ── Webhook-Driven Completion ── -- UNCHANGED; works for SPLIT too
    // since it just looks up the order by razorpayOrderId (SPLIT orders
    // have one, same as gateway-only orders) and hands off to
    // deliverAndResolve(), which now branches on paymentMode == "SPLIT".
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
    // CHANGED: refund/reversal branch now has THREE cases instead of two --
    // WALLET (wallet reversal only, unchanged), SPLIT (NEW -- reverse
    // wallet portion AND refund gateway portion), and gateway-only
    // (Razorpay refund only, unchanged).
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
            when (order.paymentMode) {
                "WALLET" -> {
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
                }
                "SPLIT" -> {
                    // NEW -- must undo BOTH legs. Attempt both even if one
                    // fails, so we don't leave the other leg un-refunded
                    // just because the first call threw.
                    val walletPortion = order.walletAmount ?: BigDecimal.ZERO
                    val gatewayPortion = order.gatewayAmount ?: BigDecimal.ZERO

                    val walletReversed = try {
                        walletCreditPort.reverseDebit(
                            userId = order.userId,
                            walletType = "NBFC",
                            amountPaise = walletPortion.multiply(BigDecimal(100)).toLong(),
                            referenceType = "RECHARGE_REFUND",
                            referenceId = order.id,
                            description = "Refund: split recharge delivery failed, wallet portion (orderId=${order.id})",
                            idempotencyKey = "recharge_split_refund_wallet_${order.id}"
                        )
                    } catch (e: Exception) {
                        log.error("SPLIT refund: wallet-portion reversal threw for orderId={}, amount=₹{}", order.id, walletPortion, e)
                        false
                    }

                    val gatewayRefunded = try {
                        razorpayClient.refund(
                            paymentId = paymentIdentifier,
                            amountPaise = gatewayPortion.multiply(BigDecimal(100)).toLong(),
                            notes = mapOf("reason" to "recharge_delivery_failed_split", "orderId" to order.id.toString())
                        )
                        true
                    } catch (e: RazorpayRefundException) {
                        log.error("SPLIT refund: gateway-portion refund failed for orderId={}, amount=₹{}, error={}",
                            order.id, gatewayPortion, e.message, e)
                        false
                    } catch (e: Exception) {
                        log.error("SPLIT refund: gateway-portion refund threw for orderId={}, amount=₹{}", order.id, gatewayPortion, e)
                        false
                    }

                    if (walletReversed && gatewayRefunded) {
                        status = "REFUNDED"
                        log.info("SPLIT refund: both legs reversed for orderId={} (wallet=₹{}, gateway=₹{})",
                            order.id, walletPortion, gatewayPortion)
                    } else {
                        log.error(
                            "SPLIT REFUND PARTIALLY/FULLY FAILED for orderId={} -- walletReversed={}, gatewayRefunded={} -- " +
                                    "customer still owed money, needs manual reconciliation.",
                            order.id, walletReversed, gatewayRefunded
                        )
                        refundFailureNote = buildString {
                            if (!walletReversed) append("Wallet portion (₹$walletPortion) reversal failed. ")
                            if (!gatewayRefunded) append("Gateway portion (₹$gatewayPortion) refund failed. ")
                            append("Needs manual reconciliation.")
                        }
                    }
                }
                else -> {
                    try {
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
                goldTxnId = order.goldTxnId,
                createdAt = order.createdAt
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
                goldTxnId = it.goldTxnId,
                createdAt = it.createdAt 
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

    // ── NEW: Stuck SPLIT-order reconciliation ──
    //
    // Handles the one gap left by "debit wallet first, then create
    // Razorpay order": what if the user never completes the Razorpay
    // checkout at all (closes the app, changes their mind, connection
    // drops)? No webhook ever fires, so deliverAndResolve() never runs,
    // and the wallet portion would stay debited indefinitely with no
    // resolution. This job finds SPLIT orders stuck in INITIATED beyond
    // SPLIT_ABANDON_THRESHOLD_MINUTES, checks the Razorpay order directly
    // (mirrors the pattern in WalletService.sweepPendingTopups()), and if
    // it was never paid, releases the wallet hold and marks the order
    // EXPIRED. A1Topup is never called for these -- delivery only happens
    // once BOTH legs are confirmed, so nothing was ever delivered here.
    @org.springframework.scheduling.annotation.Scheduled(fixedDelay = 300_000) // every 5 minutes
    suspend fun reconcileStuckSplitOrders() {
        val stuckCandidates = try {
            rechargeRepo.findByPaymentModeAndStatus("SPLIT", "INITIATED")
        } catch (e: Exception) {
            log.error("SPLIT reconciliation: failed to fetch stuck orders", e)
            return
        }

        if (stuckCandidates.isEmpty()) return

        val now = Instant.now()
        val eligible = stuckCandidates.filter { order ->
            Duration.between(order.createdAt, now).toMinutes() >= SPLIT_ABANDON_THRESHOLD_MINUTES
        }

        if (eligible.isEmpty()) return
        log.info("SPLIT reconciliation: checking {} stuck order(s)", eligible.size)

        for (order in eligible) {
            val razorpayOrderId = order.razorpayOrderId
            if (razorpayOrderId == null) {
                log.warn("SPLIT reconciliation: orderId={} has no razorpayOrderId, skipping", order.id)
                continue
            }

            try {
                val rzOrder = razorpayClient.fetchOrder(razorpayOrderId)
                if (rzOrder.status == "paid") {
                    // Payment actually went through but our webhook was
                    // missed -- do NOT release the wallet hold. Let the
                    // normal webhook-retry / manual-ops path pick this up;
                    // treating it as abandoned here would double-spend the
                    // gateway payment. Just log loudly.
                    log.warn(
                        "SPLIT reconciliation: orderId={} Razorpay status=paid but order still INITIATED -- " +
                                "likely a missed webhook, NOT releasing wallet hold. Needs webhook replay/manual check.",
                        order.id
                    )
                    continue
                }

                // Not paid after the abandon threshold -- release the
                // wallet hold and expire the order.
                val walletPortion = order.walletAmount ?: BigDecimal.ZERO
                val reversed = walletCreditPort.reverseDebit(
                    userId = order.userId,
                    walletType = "NBFC",
                    amountPaise = walletPortion.multiply(BigDecimal(100)).toLong(),
                    referenceType = "RECHARGE_SPLIT_EXPIRY_REVERSAL",
                    referenceId = order.id,
                    description = "Wallet portion released: split recharge checkout abandoned (orderId=${order.id})",
                    idempotencyKey = "recharge_split_expiry_reversal_${order.id}"
                )

                if (reversed) {
                    rechargeRepo.updateAfterConfirm(
                        id = order.id!!,
                        status = "EXPIRED",
                        razorpayPaymentId = order.razorpayPaymentId,
                        a1topupStatus = "NOT_ATTEMPTED",
                        a1topupRawResponse = toSafeJson("{\"reason\":\"split_checkout_abandoned\",\"razorpayStatus\":\"${rzOrder.status}\"}"),
                        goldAutoInvest = false,
                        goldTxnId = null,
                        failureReason = "Gateway checkout not completed within ${SPLIT_ABANDON_THRESHOLD_MINUTES} min; wallet portion auto-released"
                    )
                    log.info("SPLIT reconciliation: orderId={} expired, wallet portion ₹{} released", order.id, walletPortion)
                } else {
                    log.error(
                        "CRITICAL: SPLIT reconciliation wallet release FAILED for orderId={}, amount=₹{} -- needs manual credit",
                        order.id, walletPortion
                    )
                }
            } catch (e: Exception) {
                log.warn("SPLIT reconciliation: status check failed for orderId={} (non-fatal, will retry next cycle)", order.id, e)
            }
        }
    }

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

            if (order.paymentMode == "SPLIT") {
                val walletPortion = order.walletAmount ?: BigDecimal.ZERO
                val gatewayPortion = order.gatewayAmount ?: BigDecimal.ZERO

                val walletReversed = try {
                    walletCreditPort.reverseDebit(
                        userId = order.userId, walletType = "NBFC",
                        amountPaise = walletPortion.multiply(BigDecimal(100)).toLong(),
                        referenceType = "RECHARGE_REFUND", referenceId = order.id,
                        description = "Refund (reconciliation): split recharge delivery failed, wallet portion (orderId=${order.id})",
                        idempotencyKey = "recharge_split_refund_wallet_reconcile_${order.id}"
                    )
                } catch (e: Exception) { false }

                val gatewayRefunded = try {
                    razorpayClient.refund(
                        paymentId = order.razorpayPaymentId ?: "",
                        amountPaise = gatewayPortion.multiply(BigDecimal(100)).toLong(),
                        notes = mapOf("reason" to "recharge_delivery_failed_split_reconciliation", "orderId" to order.id.toString())
                    )
                    true
                } catch (e: Exception) { false }

                finalStatus = if (walletReversed && gatewayRefunded) "REFUNDED" else {
                    refundFailureNote = buildString {
                        if (!walletReversed) append("Wallet portion (₹$walletPortion) reversal failed. ")
                        if (!gatewayRefunded) append("Gateway portion (₹$gatewayPortion) refund failed. ")
                        append("Needs manual reconciliation.")
                    }
                    "RECHARGE_FAILED"
                }
            } else {
                try {
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