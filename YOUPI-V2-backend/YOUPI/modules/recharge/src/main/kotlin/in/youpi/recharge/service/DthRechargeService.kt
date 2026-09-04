package `in`.youpi.recharge.service

import `in`.youpi.core.Result
import `in`.youpi.core.WalletCreditPort
import `in`.youpi.core.WalletDebitOutcome
import `in`.youpi.core.WalletDebitPort
import `in`.youpi.core.razorpay.RazorpayClient
import `in`.youpi.core.razorpay.RazorpayOrderCreationException
import `in`.youpi.core.razorpay.RazorpayRefundException
import `in`.youpi.auth.repository.UserRepository
import `in`.youpi.events.PushNotificationService
import `in`.youpi.gold.GoldRewardService
import `in`.youpi.recharge.a1topup.A1TopupClient
import `in`.youpi.recharge.domain.PaymentMode
import `in`.youpi.recharge.domain.RechargeApiException
import `in`.youpi.recharge.domain.RechargeException
import `in`.youpi.recharge.domain.RechargeOrderNotFoundException
import `in`.youpi.recharge.domain.RechargeOrderResponse
import `in`.youpi.recharge.domain.RechargeStatusResponse
import `in`.youpi.recharge.domain.WalletPaymentRejectedException
import `in`.youpi.recharge.domain.dth.CreateDthRechargeRequest
import `in`.youpi.recharge.domain.dth.DthCustomerInfoResponse
import `in`.youpi.recharge.domain.dth.MPLAN_DTH_OPERATOR_CODES
import `in`.youpi.recharge.repository.RechargeOrderEntity
import `in`.youpi.recharge.repository.RechargeOrderRepository
import com.fasterxml.jackson.databind.ObjectMapper
import kotlinx.coroutines.reactor.awaitSingle
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import org.springframework.web.reactive.function.client.WebClient
import java.math.BigDecimal
import java.util.UUID

/**
 * Standalone DTH recharge service -- deliberately kept OUT of
 * RechargeService.kt. Reuses (does NOT duplicate): A1TopupClient
 * (rechargeDth()/checkStatus()), the recharge_orders table via
 * RechargeOrderRepository (serviceType="DTH" column),
 * RechargeService.reconcilePendingRecharges() (already serviceType-
 * agnostic, needs no DTH-specific change), RazorpayClient,
 * WalletDebitPort/WalletCreditPort, and GoldRewardService's reward
 * ledger/idempotency mechanism.
 *
 * Currently supports WALLET and FULL (gateway-only) payment modes only --
 * SPLIT is not wired up.
 *
 * GOLD CASHBACK: DTH has NO minimum-eligibility amount (business rule --
 * different from mobile's ₹249 floor). This is expressed by passing
 * minimumEligibleAmount = BigDecimal.ZERO into
 * GoldRewardService.creditRewardForRecharge() below -- the ledger/dedup
 * logic itself is fully shared and untouched.
 */
@Service
class DthRechargeService(
    private val rechargeRepo: RechargeOrderRepository,
    private val a1topupClient: A1TopupClient,
    private val razorpayClient: RazorpayClient,
    private val walletDebitPort: WalletDebitPort,
    private val walletCreditPort: WalletCreditPort,
    private val goldRewardService: GoldRewardService,
    // ← NEW: both already plain @Service beans reused as-is (same DI
    // pattern as goldRewardService above, just from different modules --
    // shared:events and modules:auth, both already gradle dependencies of
    // this module). No new notification service, no new user-lookup
    // service was created.
    private val pushNotificationService: PushNotificationService,
    private val userRepository: UserRepository,
    private val objectMapper: ObjectMapper,
    @Qualifier("proxiedWebClient") private val webClient: WebClient,
    @Value("\${youpi.razorpay.key-id:}") private val razorpayKeyId: String,
    @Value("\${mplan.api.key}") private val mplanApiKey: String,
    @Value("\${mplan.api.dth-info-vc-url}") private val mplanDthInfoVcUrl: String,
    @Value("\${mplan.api.dth-info-mobile-url}") private val mplanDthInfoMobileUrl: String
) {
    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        // Own constant rather than reaching into RechargeService's private
        // MIN_DELIVERABLE_AMOUNT -- same value, kept separate on purpose
        // to avoid coupling this file to RechargeService's internals.
        private val MIN_DELIVERABLE_AMOUNT = BigDecimal("29")
        private const val SERVICE_TYPE = "DTH"

        // DTH's gold-cashback eligibility floor -- NO minimum, per business
        // rule. Passed explicitly into GoldRewardService.creditRewardForRecharge()
        // so mobile's ₹249 default (in GoldRewardService itself) is never
        // touched by DTH.
        private val DTH_GOLD_REWARD_MINIMUM = BigDecimal.ZERO
    }

    // ── DTH Customer Info (mPlan) ── -- two lookup variants confirmed
    // against mPlan's docs (Sep 2026): by subscriber/VC number
    // (/dth_info) and by the customer's registered mobile number
    // (/dth_info_mobile). Both share the exact same response shape and
    // status/error handling, differing only in which query param they
    // send -- so both funnel through the private fetchDthCustomerInfo()
    // helper below rather than duplicating the parsing logic twice, same
    // pattern as A1TopupClient.doRecharge() being shared by
    // rechargeMobile()/rechargeDth(). Deliberately NOT cached (unlike
    // RechargeService.fetchPlans()) -- customer info (balance, next due
    // date, active/inactive) is exactly the kind of thing that goes stale
    // between one recharge attempt and the next, so every call hits mPlan
    // fresh. Kept here (not in RechargeService) since this is DTH-only --
    // mirrors mPlan config (apikey) + proxiedWebClient qualifier the same
    // way RechargeService does it for mobile plans/operator-check.
    suspend fun fetchDthCustomerInfoByVc(
        vcNumber: String, operator: String
    ): Result<DthCustomerInfoResponse, RechargeException> =
        fetchDthCustomerInfo(mplanDthInfoVcUrl, "vc_number", vcNumber, operator)

    suspend fun fetchDthCustomerInfoByMobile(
        mobileNumber: String, operator: String
    ): Result<DthCustomerInfoResponse, RechargeException> =
        fetchDthCustomerInfo(mplanDthInfoMobileUrl, "mobile_number", mobileNumber, operator)

    private suspend fun fetchDthCustomerInfo(
        url: String, numberParamName: String, numberParamValue: String, operator: String
    ): Result<DthCustomerInfoResponse, RechargeException> {
        val operatorCode = MPLAN_DTH_OPERATOR_CODES[operator.uppercase()]
            ?: return Result.failure(RechargeApiException(
                "No confirmed mPlan DTH operator_code for '$operator' -- only Airtel Digital TV/Sun Direct/" +
                        "Tata Play (Tata Sky)/Videocon d2h/Dish TV are mapped."
            ))

        return try {
            val uri = org.springframework.web.util.UriComponentsBuilder
                .fromHttpUrl(url)
                .queryParam("apikey", mplanApiKey.trim())
                .queryParam(numberParamName, numberParamValue)
                .queryParam("operator_code", operatorCode)
                .build().encode().toUri()

            val response = webClient.get().uri(uri).retrieve()
                .bodyToMono(String::class.java).awaitSingle()

            val root = objectMapper.readTree(response)
            if (root.path("status").asInt(0) != 1) {
                // Failure shape has been observed in two forms: a top-level
                // "records": {"msg": "..."} object (e.g. missing/invalid
                // apikey, IP not authorized) AND a "records": [{"msg": "..."}]
                // array (e.g. "Subscriber not found"). Handle both rather
                // than assuming one shape.
                val recordsNode = root.path("records")
                val errorMsg = (if (recordsNode.isArray) recordsNode.firstOrNull() else recordsNode)
                    ?.path("msg")?.asText()
                    ?.takeIf { it.isNotBlank() }
                    ?: "Unknown mPlan DTH customer-info error"
                log.warn(
                    "mPlan DTH customer-info lookup failed: paramName={}, operator={}, msg={}",
                    numberParamName, operator, errorMsg
                )
                return Result.failure(RechargeApiException(errorMsg))
            }

            val recordsNode = root.path("records")
            val record = (if (recordsNode.isArray) recordsNode.firstOrNull() else recordsNode)
                ?: return Result.failure(RechargeApiException("mPlan returned no customer record"))

            fun optText(field: String): String? =
                record.path(field).let { if (it.isMissingNode || it.isNull) null else it.asText() }
                    ?.takeIf { it.isNotBlank() }

            fun optDecimal(field: String): BigDecimal? =
                optText(field)?.let {
                    try { BigDecimal(it) } catch (e: NumberFormatException) { null }
                }

            val status = optText("status")
            Result.success(DthCustomerInfoResponse(
                custId = optText("Cust_id"),
                customerName = optText("customerName"),
                monthlyRecharge = optDecimal("MonthlyRecharge"),
                balance = optDecimal("Balance"),
                nextRechargeDate = optText("NextRechargeDate"),
                status = status,
                planName = optText("planname"),
                isActive = status?.equals("ACTIVE", ignoreCase = true) ?: false
            ))
        } catch (e: Exception) {
            log.error("mPlan DTH customer-info call failed for operator={}", operator, e)
            Result.failure(RechargeApiException("Failed to fetch DTH customer info: ${e.message}"))
        }
    }

    suspend fun createOrder(userId: UUID, req: CreateDthRechargeRequest): Result<RechargeOrderResponse, RechargeException> {
        if (req.paymentMode == PaymentMode.WALLET) {
            return createWalletPaidOrder(userId, req)
        }
        if (req.paymentMode != PaymentMode.FULL) {
            return Result.failure(RechargeApiException(
                "Payment mode ${req.paymentMode} is not supported for DTH recharges yet -- only FULL and WALLET are available."
            ))
        }

        val existing = rechargeRepo.findByIdempotencyKey(req.idempotencyKey)
        if (existing != null) {
            return Result.success(toOrderResponse(existing))
        }

        if (req.amount < MIN_DELIVERABLE_AMOUNT) {
            return Result.failure(RechargeApiException("Amount must be at least ₹$MIN_DELIVERABLE_AMOUNT"))
        }

        val amountPaise = req.amount.multiply(BigDecimal(100)).toLong()
        val razorpayOrderId = try {
            razorpayClient.createOrder(
                amountPaise = amountPaise,
                receipt = req.idempotencyKey,
                notes = mapOf(
                    "purpose" to "DTH_RECHARGE",
                    "userId" to userId.toString(),
                    "subscriberNumber" to req.subscriberNumber
                )
            ).id
        } catch (e: RazorpayOrderCreationException) {
            log.error("DTH recharge: Razorpay order creation failed for user={}: {}", userId, e.message)
            return Result.failure(RechargeApiException(e.message ?: "Razorpay order creation failed"))
        }

        val order = rechargeRepo.insertOrder(
            userId = userId,
            mobileNumber = req.subscriberNumber, // DTH subscriber/VC number reuses this column
            operator = req.operator,
            circle = null,
            planId = null,
            planAmount = req.amount,
            planDetails = "{}",
            paymentMode = req.paymentMode.name,
            emiMonths = null,
            emiAmount = null,
            status = "INITIATED",
            razorpayOrderId = razorpayOrderId,
            goldAutoInvest = false,
            idempotencyKey = req.idempotencyKey,
            planValidityDays = null,
            serviceType = SERVICE_TYPE
        )

        log.info("DTH recharge order created: orderId={}, amount={}, razorpayOrderId={}", order.id, req.amount, razorpayOrderId)

        return Result.success(
            RechargeOrderResponse(
                orderId = order.id!!,
                razorpayOrderId = razorpayOrderId,
                paymentSessionId = null,
                razorpayKeyId = razorpayKeyId,
                amount = req.amount,
                status = "INITIATED",
                paymentMode = req.paymentMode.name
            )
        )
    }

    private suspend fun createWalletPaidOrder(userId: UUID, req: CreateDthRechargeRequest): Result<RechargeOrderResponse, RechargeException> {
        val existing = rechargeRepo.findByIdempotencyKey(req.idempotencyKey)
        if (existing != null) {
            return Result.success(toOrderResponse(existing))
        }

        if (req.amount < MIN_DELIVERABLE_AMOUNT) {
            return Result.failure(RechargeApiException("Amount must be at least ₹$MIN_DELIVERABLE_AMOUNT"))
        }

        val debitOutcome = walletDebitPort.debitForService(
            userId = userId,
            walletType = "NBFC",
            amount = req.amount,
            serviceCode = "RECHARGE",
            referenceId = null,
            description = "DTH recharge ${req.subscriberNumber} (₹${req.amount})",
            idempotencyKey = "dth_recharge_debit_${req.idempotencyKey}"
        )

        when (debitOutcome) {
            is WalletDebitOutcome.Rejected -> {
                log.warn("WALLET-paid DTH recharge rejected at debit: userId={}, reason={}", userId, debitOutcome.reason)
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

        val order = try {
            rechargeRepo.insertOrder(
                userId = userId,
                mobileNumber = req.subscriberNumber,
                operator = req.operator,
                circle = null,
                planId = null,
                planAmount = req.amount,
                planDetails = "{}",
                paymentMode = req.paymentMode.name,
                emiMonths = null,
                emiAmount = null,
                status = "INITIATED",
                razorpayOrderId = null,
                goldAutoInvest = false,
                idempotencyKey = req.idempotencyKey,
                planValidityDays = null,
                serviceType = SERVICE_TYPE
            )
        } catch (e: Exception) {
            log.error(
                "WALLET-paid DTH recharge: insertOrder FAILED after wallet debit -- reversing. userId={}, amount=₹{}, error={}",
                userId, req.amount, e.message, e
            )
            val reversed = walletCreditPort.reverseDebit(
                userId = userId,
                walletType = "NBFC",
                amountPaise = req.amount.multiply(BigDecimal(100)).toLong(),
                referenceType = "RECHARGE",
                referenceId = null,
                description = "Reversal: DTH recharge order could not be created (${req.subscriberNumber})",
                idempotencyKey = "dth_recharge_wallet_insert_failure_reversal_${req.idempotencyKey}"
            )
            if (!reversed) {
                log.error(
                    "CRITICAL: WALLET-paid DTH recharge wallet reversal FAILED after insertOrder failure -- " +
                            "userId={}, amount=₹{}, idempotencyKey={} -- needs manual wallet credit.",
                    userId, req.amount, req.idempotencyKey
                )
            }
            return Result.failure(RechargeApiException(e.message ?: "Could not create DTH recharge order"))
        }

        log.info("DTH recharge order created (WALLET paid): orderId={}, amount=₹{}, userId={}", order.id, req.amount, userId)

        deliverAndResolve(order, paymentIdentifier = "WALLET-${order.id}")

        val finalOrder = rechargeRepo.findById(order.id!!) ?: order
        return Result.success(toOrderResponse(finalOrder))
    }

    /**
     * DTH-only delivery + refund + gold-reward logic. Intentionally NOT
     * calling into RechargeService.deliverAndResolve() -- duplicates the
     * WALLET/gateway-only refund branches (not SPLIT -- unreachable for
     * DTH) to keep this file self-contained, per the earlier decision to
     * accept that duplication rather than share a helper.
     */
    private suspend fun deliverAndResolve(order: RechargeOrderEntity, paymentIdentifier: String): Boolean {
        var status = "PAYMENT_DONE"
        var a1topupStatus: String
        var a1topupRawResponse: String

        try {
            val result = a1topupClient.rechargeDth(
                subscriberNumber = order.mobileNumber,
                operator = order.operator,
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
                    log.warn("A1Topup DTH: response ambiguous for orderId={}, needs Status API check", order.id)
                    "PENDING_VERIFICATION"
                }
                else -> {
                    status = "RECHARGE_FAILED"
                    log.error("A1Topup DTH: recharge failed for orderId={}, reason={}", order.id, result.errorMessage)
                    "FAILED"
                }
            }
        } catch (e: Exception) {
            log.error(
                "A1Topup DTH: recharge call threw for orderId={} -- treating as failure for refund purposes",
                order.id, e
            )
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
                        description = "Refund: DTH recharge delivery failed (orderId=${order.id})",
                        idempotencyKey = "dth_recharge_refund_${order.id}"
                    )
                    if (reversed) {
                        status = "REFUNDED"
                        log.info("Wallet reversal credited for DTH orderId={} after A1Topup failure", order.id)
                    } else {
                        log.error("WALLET REVERSAL FAILED for DTH orderId={} -- customer still owed money, needs manual wallet credit.", order.id)
                        refundFailureNote = "Auto wallet-reversal failed. Needs manual credit."
                    }
                } catch (e: Exception) {
                    log.error("WALLET REVERSAL FAILED for DTH orderId={} -- needs manual wallet credit. Error: {}", order.id, e.message, e)
                    refundFailureNote = "Auto wallet-reversal failed: ${e.message}. Needs manual credit."
                }
            } else {
                try {
                    val refund = razorpayClient.refund(
                        paymentId = paymentIdentifier,
                        amountPaise = order.planAmount.multiply(BigDecimal(100)).toLong(),
                        notes = mapOf("reason" to "dth_recharge_delivery_failed", "orderId" to order.id.toString())
                    )
                    status = "REFUNDED"
                    log.info("Razorpay refund issued for DTH orderId={} after A1Topup failure: refundId={}, status={}", order.id, refund.id, refund.status)
                } catch (e: RazorpayRefundException) {
                    log.error("REFUND FAILED for DTH orderId={} -- needs manual refund via Razorpay dashboard. Error: {}", order.id, e.message, e)
                    refundFailureNote = "Auto-refund failed: ${e.message}. Needs manual refund."
                } catch (e: Exception) {
                    log.error("REFUND FAILED for DTH orderId={} -- needs manual refund via Razorpay dashboard. Error: {}", order.id, e.message, e)
                    refundFailureNote = "Auto-refund failed: ${e.message}. Needs manual refund."
                }
            }
        }

        // ← CHANGED: was updateAfterConfirm() (unconditional WHERE id=:id).
        // Now updateAfterConfirmIfStatus() with expectedCurrentStatus =
        // "INITIATED" -- the exact status handleWebhookCaptured() already
        // confirmed the order was in right before calling this function.
        // In the normal (non-racing) case this is identical to before. It
        // only differs if a duplicate Razorpay webhook delivery for the
        // same DTH order reached this same point concurrently -- the loser
        // gets null instead of silently duplicating the winner's work
        // (including a duplicate push, which -- unlike gold reward -- has
        // no ledger of its own to dedupe it).
        val updatedOrder = rechargeRepo.updateAfterConfirmIfStatus(
            id = order.id!!,
            expectedCurrentStatus = "INITIATED",
            status = status,
            razorpayPaymentId = paymentIdentifier,
            a1topupStatus = a1topupStatus,
            a1topupRawResponse = toSafeJson(a1topupRawResponse),
            goldAutoInvest = false,
            goldTxnId = null,
            failureReason = refundFailureNote
        ) ?: run {
            log.info("DTH webhook: orderId={} was already resolved by a concurrent call, skipping duplicate reward/push", order.id)
            return true
        }

        log.info("DTH recharge confirmed: orderId={}, amount={}, paymentMode={}", updatedOrder.id, updatedOrder.planAmount, order.paymentMode)

        // ← NEW: gold-coin cashback, ONLY on confirmed RECHARGE_SUCCESS --
        // never on PAYMENT_DONE/PENDING_VERIFICATION/FAILED/REFUNDED.
        // minimumEligibleAmount = ZERO -- DTH has no minimum, unlike
        // mobile's ₹249 default inside GoldRewardService. The ledger's
        // rechargeTxnId-based insertIfNotExists (unchanged, shared with
        // mobile) is what actually guarantees exactly-once credit even if
        // this path AND reconciliation's resolveA1TopupOutcome() both
        // reach a SUCCESS resolution for the same order (they can't both
        // fire for the same order in practice -- see status guards -- but
        // the ledger dedup makes it safe even if that assumption is ever
        // wrong).
        if (updatedOrder.status == "RECHARGE_SUCCESS") {
            try {
                goldRewardService.creditRewardForRecharge(
                    userId = order.userId,
                    rechargeTxnId = updatedOrder.id.toString(),
                    rechargeAmount = updatedOrder.planAmount,
                    minimumEligibleAmount = DTH_GOLD_REWARD_MINIMUM
                )
                log.info("DTH gold coin reward credited: orderId={}, planAmount={}", updatedOrder.id, updatedOrder.planAmount)
            } catch (e: Exception) {
                log.warn("DTH gold coin reward crediting failed (non-fatal): orderId={}, reason={}", updatedOrder.id, e.message)
            }

            // ← NEW: reuses the existing, already service-type-agnostic
            // PushNotificationService.sendRechargeSuccessPush() -- no new
            // notification service or template. Reward numbers come from
            // GoldRewardService.previewReward(), the same pure helper the
            // credit call above conceptually mirrors (identical threshold,
            // identical rounding), so the push always shows exactly what
            // was just credited above. Gated the same way as the credit
            // call: only reachable when updatedOrder.status ==
            // "RECHARGE_SUCCESS", i.e. never on PAYMENT_DONE,
            // PENDING_VERIFICATION, FAILED, or REFUNDED, and never on
            // Razorpay payment-capture alone.
            try {
                val preview = GoldRewardService.previewReward(updatedOrder.planAmount, DTH_GOLD_REWARD_MINIMUM)
                if (preview != null) {
                    val user = userRepository.findById(order.userId)
                    pushNotificationService.sendRechargeSuccessPush(
                        fcmToken = user?.fcmToken,
                        orderId = updatedOrder.id.toString(),
                        amountRupees = updatedOrder.planAmount,
                        earnedCoins = preview.earnedCoins,
                        earnedValueRupees = preview.earnedValueRupees
                    )
                    log.info("DTH push notification sent: orderId={}", updatedOrder.id)
                }
            } catch (e: Exception) {
                log.warn("DTH push notification dispatch failed (non-fatal): orderId={}, reason={}", updatedOrder.id, e.message)
            }
        }

        return true
    }

    /**
     * Called from PaymentService's Razorpay webhook dispatcher, AFTER
     * RechargeService.handleWebhookCaptured() has already returned false
     * for this order (its serviceType guard rejects non-MOBILE orders).
     * Returns false itself if no matching order is found OR the matching
     * order isn't a DTH order -- symmetric safety check, in case this is
     * ever called in a different order/context.
     */
    suspend fun handleWebhookCaptured(razorpayOrderId: String, razorpayPaymentId: String): Boolean {
        val order = rechargeRepo.findByRazorpayOrderId(razorpayOrderId) ?: run {
            log.debug("DTH webhook: no order for razorpayOrderId={}", razorpayOrderId)
            return false
        }
        if (order.serviceType != SERVICE_TYPE) return false

        if (order.status != "INITIATED") {
            log.info("DTH webhook: order already processed (status={}), skipping orderId={}", order.status, order.id)
            return true
        }

        return deliverAndResolve(order, razorpayPaymentId)
    }

    suspend fun getOrderStatus(userId: UUID, orderId: UUID): Result<RechargeStatusResponse, RechargeException> {
        val order = rechargeRepo.findById(orderId)
            ?: return Result.failure(RechargeOrderNotFoundException(orderId))

        if (order.userId != userId || order.serviceType != SERVICE_TYPE) {
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
                createdAt = order.createdAt,
                serviceType = order.serviceType
            )
        )
    }

    private fun toOrderResponse(order: RechargeOrderEntity): RechargeOrderResponse = RechargeOrderResponse(
        orderId = order.id!!,
        razorpayOrderId = order.razorpayOrderId,
        paymentSessionId = null,
        amount = order.planAmount,
        status = order.status,
        paymentMode = order.paymentMode
    )

    private fun toSafeJson(raw: String): String {
        return try {
            objectMapper.readTree(raw)
            raw
        } catch (e: Exception) {
            objectMapper.writeValueAsString(mapOf("raw" to raw))
        }
    }
}