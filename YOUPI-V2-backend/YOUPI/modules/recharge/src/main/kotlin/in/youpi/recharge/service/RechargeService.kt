package `in`.youpi.recharge.service

import `in`.youpi.core.Result
import `in`.youpi.core.razorpay.RazorpayClient
import `in`.youpi.core.razorpay.RazorpayOrderCreationException
import `in`.youpi.invest.service.InvestService
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
    private val webClient: WebClient,                          // ← bean inject karo, direct build nahi
    private val investService: InvestService,                   // ← recharge → auto gold-invest ke liye
    private val razorpayClient: RazorpayClient,
    @Value("\${mplan.api.key}") private val mplanApiKey: String,
    @Value("\${mplan.api.plans-url}") private val mplanPlansUrl: String,
    @Value("\${mplan.api.mobile-plans-url}") private val mplanMobilePlansUrl: String,
    @Value("\${mplan.api.operator-check-url}") private val mplanOperatorCheckUrl: String,
    @Value("\${youpi.recharge.gold-invest-percentage:1.0}") private val goldInvestPercentage: BigDecimal
) {
    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        private val PLAN_CACHE_TTL = Duration.ofMinutes(30)
        private const val PLAN_CACHE_PREFIX = "plans:"

        // Gold auto-invest is a promo tied to the ₹249 plan specifically, not
        // "any recharge amount x goldInvestPercentage". Compared with
        // compareTo (not ==) because BigDecimal("249") != BigDecimal("249.00")
        // under equals(), but compareTo treats them as equal in value.
        private val GOLD_ELIGIBLE_PLAN_AMOUNT = BigDecimal("249")
    }

    // ── Plan Fetching (Redis Cached) ──

    // mPlan requires numeric operator_code / circle_code, not free-text names.
    // These mappings come from mPlan's dashboard (Operator Codes / Circle
    // Codes tables) — update here if mPlan adds/changes codes.
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
            val response = webClient.get()
                .uri("$mplanMobilePlansUrl?apikey=$mplanApiKey&operator_code=$operatorCode&circle_code=$circleCode")
                .retrieve()
                .bodyToMono(String::class.java)
                .awaitSingle()

            val root = objectMapper.readTree(response)

            // mPlan returns {"status": 0, "records": {"msg": "..."}} on
            // failure (bad key, bad IP, bad params) and {"status": 1,
            // "records": {<category>: [...plans]}, ...} on success.
            if (root.path("status").asInt(0) != 1) {
                val errorMsg = root.path("records").path("msg").asText("Unknown mPlan API error")
                log.error("mPlan API returned failure status: operator={}, circle={}, msg={}", operator, circle, errorMsg)
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

            val json = objectMapper.writeValueAsString(plans)
            redisTemplate.opsForValue().set(cacheKey, json, PLAN_CACHE_TTL).awaitSingleOrNull()

            log.info("Plans fetched from mPlan API: operator={}, circle={}, count={}", operator, circle, plans.size)
            Result.success(plans)
        } catch (e: Exception) {
            log.error("mPlan API call failed for operator={}, circle={}", operator, circle, e)
            Result.failure(RechargeApiException("Failed to fetch plans: ${e.message}"))
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
            idempotencyKey = req.idempotencyKey
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

        // ── Deliver the actual recharge ──
        // TODO(A1Topup): no A1Topup client exists in this codebase yet --
        // mPlan is wired for plan *fetching* only, not recharge *delivery*.
        // Once A1Topup API docs + credentials are available, replace this
        // block with a real call, map its response into
        // a1topupStatus/a1topupTxnId/a1topupRawResponse below, and set
        // status to RECHARGE_SUCCESS/RECHARGE_FAILED accordingly. Until
        // then, PAYMENT_DONE is the honest state -- payment is confirmed,
        // actual delivery to the operator hasn't happened. (Note: 'SUCCESS'
        // was never a valid value here -- chk_recharge_status only allows
        // INITIATED/PAYMENT_DONE/RECHARGE_PENDING/RECHARGE_SUCCESS/
        // RECHARGE_FAILED/REFUNDED. Writing 'SUCCESS' always violated the
        // constraint; it just never surfaced until webhook delivery
        // actually reached this code path for the first time.)
        val a1topupStatus = "PENDING_DELIVERY"
        log.warn("Recharge webhook: payment captured but A1Topup delivery is not yet implemented -- orderId={} left as a1topupStatus=PENDING_DELIVERY", order.id)

        var updatedOrder = rechargeRepo.updateAfterConfirm(
            id = order.id!!,
            status = "PAYMENT_DONE",
            razorpayPaymentId = razorpayPaymentId,
            a1topupStatus = a1topupStatus,
            a1topupRawResponse = order.a1topupRawResponse ?: "null",
            goldAutoInvest = order.goldAutoInvest,
            goldTxnId = order.goldTxnId
        )

        log.info("Recharge confirmed via webhook: orderId={}, amount={}", updatedOrder.id, updatedOrder.planAmount)

        // ── Auto gold-invest — ₹249 plan only, non-fatal ──
        if (updatedOrder.planAmount.compareTo(GOLD_ELIGIBLE_PLAN_AMOUNT) == 0) {
            val goldAmount = updatedOrder.planAmount
                .multiply(goldInvestPercentage)
                .divide(BigDecimal(100), 2, java.math.RoundingMode.HALF_EVEN)

            if (goldAmount > BigDecimal.ZERO) {
                try {
                    val goldResult = investService.buyGold(
                        userId = order.userId,
                        amountInr = goldAmount,
                        idempotencyKey = "recharge-gold-${updatedOrder.id}",
                        triggeredBy = "AUTO_RECHARGE"
                    )

                    when (goldResult) {
                        is Result.Success -> {
                            rechargeRepo.updateAfterConfirm(
                                id = updatedOrder.id!!,
                                status = updatedOrder.status,
                                razorpayPaymentId = updatedOrder.razorpayPaymentId,
                                a1topupStatus = updatedOrder.a1topupStatus,
                                a1topupRawResponse = updatedOrder.a1topupRawResponse ?: "null",
                                goldAutoInvest = true,
                                goldTxnId = goldResult.value.txnId
                            )
                            log.info("Auto gold-invest succeeded: orderId={}, goldTxnId={}, amount={}",
                                updatedOrder.id, goldResult.value.txnId, goldAmount)
                        }
                        is Result.Failure -> {
                            // Non-fatal by design -- recharge itself already
                            // succeeded (or is pending delivery); a gold-side
                            // failure (e.g. Augmont down) shouldn't roll that
                            // back. User just doesn't get the bonus gold this
                            // time; ops can reconcile from the warning in logs.
                            log.warn("Auto gold-invest failed (non-fatal): orderId={}, reason={}",
                                updatedOrder.id, goldResult.error.message)
                        }
                    }
                } catch (e: Exception) {
                    log.error("Auto gold-invest threw unexpected exception (non-fatal): orderId={}", updatedOrder.id, e)
                }
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

        val goldEligible = order.planAmount.compareTo(GOLD_ELIGIBLE_PLAN_AMOUNT) == 0
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

}