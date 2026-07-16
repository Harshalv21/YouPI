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
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

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
    @Value("\${youpi.razorpay.key-secret:}") private val razorpayKeySecret: String,
    @Value("\${youpi.recharge.gold-invest-percentage:1.0}") private val goldInvestPercentage: BigDecimal
) {
    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        private val PLAN_CACHE_TTL = Duration.ofMinutes(30)
        private const val PLAN_CACHE_PREFIX = "plans:"
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

    // ── Confirm Recharge (payment capture → A1Topup → gold auto-invest) ──

    /**
     * Confirms a recharge after client-side Razorpay payment success.
     *
     * Flow:
     *  1. Verify Razorpay HMAC signature (same pattern as PaymentService)
     *  2. Mark order SUCCESS
     *  3. TODO: call A1Topup API to actually deliver the recharge
     *  4. Auto-invest a small % of the recharge amount into gold (non-fatal —
     *     recharge stays SUCCESS even if this step fails; user just doesn't
     *     get the gold-coin animation, and a warning is returned instead)
     */
    suspend fun confirmRecharge(userId: UUID, req: ConfirmRechargeRequest): Result<ConfirmRechargeResponse, RechargeException> {
        val order = rechargeRepo.findById(req.rechargeOrderId)
            ?: return Result.failure(RechargeOrderNotFoundException(req.rechargeOrderId))

        if (order.userId != userId) {
            return Result.failure(RechargeOrderNotFoundException(req.rechargeOrderId))
        }

        if (order.status == "SUCCESS") {
            return Result.failure(RechargeAlreadyConfirmedException(order.id!!))
        }

        // ── Verify Razorpay signature ──
        val payload = "${req.razorpayOrderId}|${req.razorpayPaymentId}"
        if (!verifyHmacSignature(payload, req.razorpaySignature, razorpayKeySecret)) {
            return Result.failure(PaymentVerificationException())
        }

        // ── Mark order SUCCESS ──
        // TODO: Real A1Topup API call yahan aayega (actual mobile recharge delivery).
        // Abhi ke liye status seedha SUCCESS maan rahe hain payment-capture ke baad.
        var updatedOrder = rechargeRepo.updateAfterConfirm(
            id = order.id!!,
            status = "SUCCESS",
            razorpayPaymentId = req.razorpayPaymentId,
            a1topupStatus = "SUCCESS",
            a1topupRawResponse = order.a1topupRawResponse ?: "null",
            goldAutoInvest = order.goldAutoInvest,
            goldTxnId = order.goldTxnId
        )

        log.info("Recharge confirmed: orderId={}, amount={}", updatedOrder.id, updatedOrder.planAmount)

        // ── Auto gold-invest (non-fatal) ──
        var goldWarning: String? = null
        var goldTxnId: UUID? = null
        var goldAutoInvest = false
        val goldAmount = updatedOrder.planAmount
            .multiply(goldInvestPercentage)
            .divide(BigDecimal(100), 2, java.math.RoundingMode.HALF_EVEN)

        if (goldAmount > BigDecimal.ZERO) {
            try {
                val goldResult = investService.buyGold(
                    userId = userId,
                    amountInr = goldAmount,
                    idempotencyKey = "recharge-gold-${updatedOrder.id}",
                    triggeredBy = "AUTO_RECHARGE"
                )

                when (goldResult) {
                    is Result.Success -> {
                        goldTxnId = goldResult.value.txnId
                        goldAutoInvest = true
                        updatedOrder = rechargeRepo.updateAfterConfirm(
                            id = updatedOrder.id!!,
                            status = updatedOrder.status,
                            razorpayPaymentId = updatedOrder.razorpayPaymentId,
                            a1topupStatus = updatedOrder.a1topupStatus,
                            a1topupRawResponse = updatedOrder.a1topupRawResponse ?: "null",
                            goldAutoInvest = true,
                            goldTxnId = goldTxnId
                        )
                        log.info("Auto gold-invest succeeded: orderId={}, goldTxnId={}, amount={}",
                            updatedOrder.id, goldTxnId, goldAmount)
                    }
                    is Result.Failure -> {
                        goldWarning = "Gold investment could not be completed: ${goldResult.error.message}"
                        log.warn("Auto gold-invest failed (non-fatal): orderId={}, reason={}",
                            updatedOrder.id, goldResult.error.message)
                    }
                }
            } catch (e: Exception) {
                // Belt-and-suspenders — buyGold ke andar bhi try-catch hai, par
                // koi unexpected exception (e.g. Augmont user mapping missing)
                // recharge ko fail nahi karni chahiye.
                goldWarning = "Gold investment could not be completed: ${e.message}"
                log.error("Auto gold-invest threw unexpected exception (non-fatal): orderId={}", updatedOrder.id, e)
            }
        }

        return Result.success(
            ConfirmRechargeResponse(
                orderId = updatedOrder.id!!,
                status = updatedOrder.status,
                a1TopupStatus = updatedOrder.a1topupStatus,
                goldAutoInvest = goldAutoInvest,
                goldTxnId = goldTxnId,
                goldInvestAmount = if (goldAutoInvest) goldAmount else null,
                goldWarning = goldWarning
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

    // ── HMAC Verification (same pattern as PaymentService) ──

    private fun verifyHmacSignature(payload: String, expectedSignature: String, secret: String): Boolean {
        // Same fix as PaymentService: fail closed, not open, when unconfigured.
        if (secret.isBlank()) {
            log.error("Razorpay HMAC secret not configured -- rejecting signature verification")
            return false
        }

        return try {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(secret.toByteArray(), "HmacSHA256"))
            val computedHex = mac.doFinal(payload.toByteArray())
                .joinToString("") { "%02x".format(it) }
            computedHex.equals(expectedSignature, ignoreCase = true)
        } catch (e: Exception) {
            log.error("HMAC verification error", e)
            false
        }
    }
}