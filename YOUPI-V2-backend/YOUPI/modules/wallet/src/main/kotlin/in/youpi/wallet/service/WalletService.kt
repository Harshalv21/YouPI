package `in`.youpi.wallet.service

import `in`.youpi.core.BaseException
import `in`.youpi.core.Result
import `in`.youpi.core.WalletCreditPort
import `in`.youpi.core.WalletDebitOutcome
import `in`.youpi.core.WalletDebitPort
import `in`.youpi.core.WalletDebitRejectionReason
import `in`.youpi.core.cashfree.CashfreeClient
import `in`.youpi.core.cashfree.CashfreeOrderCreationException
import `in`.youpi.core.ratelimit.RateLimiterService
import `in`.youpi.payment.repository.PaymentOrderEntity
import `in`.youpi.payment.repository.PaymentOrderRepository
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.core.R2dbcEntityTemplate
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.r2dbc.connection.R2dbcTransactionManager
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import org.springframework.transaction.reactive.TransactionalOperator
import org.springframework.transaction.reactive.executeAndAwait
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.util.UUID

// ── Entities ──

@Table("wallets")
data class WalletEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val walletType: String,
    val balance: BigDecimal = BigDecimal.ZERO,
    val currency: String = "INR",
    val isActive: Boolean = true,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface WalletRepository : CoroutineCrudRepository<WalletEntity, UUID> {
    suspend fun findByUserIdAndWalletType(userId: UUID, walletType: String): WalletEntity?
    suspend fun findAllByUserId(userId: UUID): List<WalletEntity>
    // suspend fun findByMobile(mobile: String): WalletEntity?   // ← recipient lookup ke liye

    @Query("UPDATE wallets SET balance = balance + :amount, updated_at = NOW() WHERE id = :id AND balance + :amount >= 0 RETURNING id")
    suspend fun atomicBalanceUpdate(id: UUID, amount: BigDecimal): Int
}

interface UserLookupRepository : CoroutineCrudRepository<UserLookupEntity, UUID>

@Table("users")
data class UserLookupEntity(
    @Id val id: UUID? = null,
    val mobile: String
)

@Table("ledger_entries")
data class LedgerEntryEntity(
    @Id val id: UUID? = null,
    val walletId: UUID,
    val txnDirection: String,
    val amount: BigDecimal,
    val balanceBefore: BigDecimal,
    val balanceAfter: BigDecimal,
    val referenceType: String,
    val referenceId: UUID? = null,
    val description: String? = null,
    val idempotencyKey: String? = null,
    val createdAt: Instant = Instant.now()
)

interface LedgerEntryRepository : CoroutineCrudRepository<LedgerEntryEntity, UUID> {
    @Query("SELECT * FROM ledger_entries WHERE wallet_id = :walletId ORDER BY created_at DESC LIMIT :limit OFFSET :offset")
    suspend fun findByWalletId(walletId: UUID, limit: Int = 20, offset: Int = 0): List<LedgerEntryEntity>

    suspend fun findByIdempotencyKey(idempotencyKey: String): LedgerEntryEntity?
}

// ── DTOs ──

data class WalletBalanceResponse(
    val userId: UUID,
    val wallets: List<WalletInfo>
)

data class WalletInfo(
    val walletId: UUID,
    val type: String,
    val balance: BigDecimal,
    val currency: String,
    val isActive: Boolean
)

// ← NAYA: wallet topup order DTOs
data class CreateWalletTopupOrderRequest(
    val amountRupees: BigDecimal
)

data class CreateWalletTopupOrderResponse(
    val orderId: String,
    val paymentSessionId: String,   // NEW -- Cashfree checkout needs this
    val amount: Long,       // paise
    val currency: String,
    val receipt: String?
)

// ← NAYA: Add Money screen ka post-checkout polling response
data class WalletTopupStatusResponse(
    val orderId: String,
    val status: String,   // CREATED, PENDING, CAPTURED, FAILED, REFUNDED, DISPUTED
    val amount: Long       // paise
)

// ── Exceptions ──

sealed class WalletException(code: String, message: String, httpStatus: Int = 400)
    : BaseException(code, message) { override val httpStatus: Int = httpStatus }

class InsufficientBalanceException(val available: BigDecimal, val required: BigDecimal) : WalletException(
    "INSUFFICIENT_BALANCE", "Insufficient balance: available=₹$available, required=₹$required", 402
)

class WalletNotFoundException(userId: UUID, walletType: String) : WalletException(
    "WALLET_NOT_FOUND", "Wallet $walletType not found for user $userId", 404
)

// ← NAYA: topup order creation exception
class TopupOrderCreationException(reason: String) : WalletException(
    "TOPUP_ORDER_FAILED", "Unable to create topup order: $reason", 502
)

class TopupRateLimitExceededException : WalletException(
    "TOPUP_RATE_LIMIT_EXCEEDED", "Too many topup attempts, please try again in a minute", 429
)

class TopupOrderNotFoundException(orderId: String) : WalletException(
    "TOPUP_ORDER_NOT_FOUND", "No wallet top-up order found for $orderId", 404
)

@Service
class WalletService(
    private val walletRepo: WalletRepository,
    private val ledgerRepo: LedgerEntryRepository,
    private val userLookupRepo: UserLookupRepository,            // ← naya
    private val txManager: R2dbcTransactionManager,               // ← @Transactional replace
    private val cashfreeClient: CashfreeClient,                          // ← Cashfree (Razorpay hataya gaya)
    private val rateLimiterService: RateLimiterService,                    // ← NAYA (rate limit)
    private val paymentRepo: PaymentOrderRepository                        // ← NAYA: wallet topup orders persist karne ke liye (payment_orders, purpose='WALLET_TOPUP')
) : WalletCreditPort, WalletDebitPort {

    // ← NAYA: service_code allowlist. Wallet MVP scope decision -- sirf
    // RECHARGE allowed abhi (Gold Purchase baad mein add hoga). Hardcoded
    // hai kyunki ek hi entry hai -- DB table ka overhead nahi chahiye.
    // Extend karna easy hai jab Gold Purchase ready ho: bas is set mein
    // "GOLD_PURCHASE" add karo.
    private val serviceCodeAllowlist = setOf("RECHARGE")
    private val log = LoggerFactory.getLogger(javaClass)
    private val txOperator = TransactionalOperator.create(txManager)  // ← reactive tx

    suspend fun getBalance(userId: UUID): WalletBalanceResponse {
        var wallets = walletRepo.findAllByUserId(userId)

        if (wallets.isEmpty()) {
            log.info("No wallets found for user {}, creating default NBFC wallet", userId)
            val defaultWallet = walletRepo.save(WalletEntity(userId = userId, walletType = "NBFC"))
            wallets = listOf(defaultWallet)
        }

        return WalletBalanceResponse(
            userId = userId,
            wallets = wallets.map {
                WalletInfo(it.id!!, it.walletType, it.balance, it.currency, it.isActive)
            }
        )
    }

    suspend fun credit(
        userId: UUID,
        walletType: String,
        amount: BigDecimal,
        referenceType: String,
        referenceId: UUID? = null,
        description: String? = null,
        idempotencyKey: String
    ): Result<WalletInfo, WalletException> {
        val existingLedger = ledgerRepo.findByIdempotencyKey(idempotencyKey)
        if (existingLedger != null) {
            val wallet = walletRepo.findById(existingLedger.walletId)!!
            return Result.success(WalletInfo(wallet.id!!, wallet.walletType, wallet.balance, wallet.currency, wallet.isActive))
        }

        val wallet = walletRepo.findByUserIdAndWalletType(userId, walletType)
            ?: return Result.failure(WalletNotFoundException(userId, walletType))

        return txOperator.executeAndAwait {                      // ← reactive transaction
            val balanceBefore = wallet.balance
            val rowsAffected = walletRepo.atomicBalanceUpdate(wallet.id!!, amount)
            if (rowsAffected == 0) return@executeAndAwait Result.failure(WalletNotFoundException(userId, walletType))
            val updated = walletRepo.findById(wallet.id)!!

            ledgerRepo.save(LedgerEntryEntity(
                walletId = wallet.id,
                txnDirection = "CREDIT",
                amount = amount,
                balanceBefore = balanceBefore,
                balanceAfter = updated.balance,
                referenceType = referenceType,
                referenceId = referenceId,
                description = description,
                idempotencyKey = idempotencyKey
            ))

            log.info("Wallet CREDIT: userId={}, type={}, amount=₹{}, newBalance=₹{}", userId, walletType, amount, updated.balance)
            Result.success(WalletInfo(updated.id!!, updated.walletType, updated.balance, updated.currency, updated.isActive))
        }!!
    }

    suspend fun debit(
        userId: UUID,
        walletType: String,
        amount: BigDecimal,
        referenceType: String,
        referenceId: UUID? = null,
        description: String? = null,
        idempotencyKey: String
    ): Result<WalletInfo, WalletException> {
        val existingLedger = ledgerRepo.findByIdempotencyKey(idempotencyKey)
        if (existingLedger != null) {
            val wallet = walletRepo.findById(existingLedger.walletId)!!
            return Result.success(WalletInfo(wallet.id!!, wallet.walletType, wallet.balance, wallet.currency, wallet.isActive))
        }

        val wallet = walletRepo.findByUserIdAndWalletType(userId, walletType)
            ?: return Result.failure(WalletNotFoundException(userId, walletType))

        if (wallet.balance < amount) {
            return Result.failure(InsufficientBalanceException(wallet.balance, amount))
        }

        return txOperator.executeAndAwait {                      // ← reactive transaction
            val balanceBefore = wallet.balance
            val rowsAffected = walletRepo.atomicBalanceUpdate(wallet.id!!, amount.negate())
            if (rowsAffected == 0) return@executeAndAwait Result.failure(InsufficientBalanceException(wallet.balance, amount))
            val updated = walletRepo.findById(wallet.id)!!

            ledgerRepo.save(LedgerEntryEntity(
                walletId = wallet.id,
                txnDirection = "DEBIT",
                amount = amount,
                balanceBefore = balanceBefore,
                balanceAfter = updated.balance,
                referenceType = referenceType,
                referenceId = referenceId,
                description = description,
                idempotencyKey = idempotencyKey
            ))

            log.info("Wallet DEBIT: userId={}, type={}, amount=₹{}, newBalance=₹{}", userId, walletType, amount, updated.balance)
            Result.success(WalletInfo(updated.id!!, updated.walletType, updated.balance, updated.currency, updated.isActive))
        }!!
    }

    // ← NAYA: Add Money screen ke payment-confirmation polling ke liye
    // (recharge ke getOrderStatus() jaisa hi pattern). Ownership check --
    // sirf apna hi order dekh sakta hai.
    suspend fun getTopupOrderStatus(userId: UUID, cashfreeOrderId: String): Result<WalletTopupStatusResponse, WalletException> {
        val order = paymentRepo.findByRazorpayOrderId(cashfreeOrderId)
            ?: return Result.failure(TopupOrderNotFoundException(cashfreeOrderId))

        if (order.userId != userId || order.purpose != "WALLET_TOPUP") {
            return Result.failure(TopupOrderNotFoundException(cashfreeOrderId))
        }

        return Result.success(
            WalletTopupStatusResponse(
                orderId = cashfreeOrderId,
                status = order.status,
                amount = order.amountPaise
            )
        )
    }

    suspend fun createWallet(userId: UUID, walletType: String): WalletEntity {
        val existing = walletRepo.findByUserIdAndWalletType(userId, walletType)
        if (existing != null) return existing
        return walletRepo.save(WalletEntity(userId = userId, walletType = walletType))
    }

    suspend fun getLedger(userId: UUID, walletType: String, page: Int = 0, pageSize: Int = 20): List<LedgerEntryEntity> {
        val wallet = walletRepo.findByUserIdAndWalletType(userId, walletType) ?: return emptyList()
        return ledgerRepo.findByWalletId(wallet.id!!, pageSize, page * pageSize)
    }

    // ← Wallet topup ke liye Cashfree order create karta hai (Razorpay hataya gaya)
    suspend fun createTopupOrder(
        userId: UUID,
        amountRupees: BigDecimal
    ): Result<CreateWalletTopupOrderResponse, WalletException> {

        if (amountRupees <= BigDecimal.ZERO) {
            return Result.failure(TopupOrderCreationException("Amount must be greater than zero"))
        }

        // ← NAYA: distributed rate limit — 5 order attempts per user per 60s
        val rateLimitKey = "rl:wallet:topup:$userId"
        val allowed = rateLimiterService.isAllowed(rateLimitKey, limit = 5, windowSeconds = 60)
        if (!allowed) {
            log.warn("Rate limit exceeded for wallet topup: userId={}", userId)
            return Result.failure(TopupRateLimitExceededException())
        }

        val shortUserId = userId.toString().take(8)
        val receipt = "wtop_${shortUserId}_${System.currentTimeMillis()}"

        // Cashfree requires customer_phone at order-creation time (Razorpay
        // didn't need this) -- fetched via the same UserLookupRepository
        // already used for recipient resolution elsewhere in this file.
        val userMobile = userLookupRepo.findById(userId)?.mobile
            ?: return Result.failure(TopupOrderCreationException("User mobile number not found"))

        return try {
            val order = cashfreeClient.createOrder(
                amountRupees = amountRupees.toDouble(),
                orderId = receipt,
                customerId = userId.toString(),
                customerPhone = userMobile
            )

            log.info("Topup order created: userId={}, orderId={}, amount=₹{}", userId, order.orderId, amountRupees)

            // Ensure a NBFC wallet exists for this user (getBalance() already
            // does this lazily elsewhere, but createTopupOrder can be the
            // very first wallet interaction for a brand-new user).
            val wallet = walletRepo.findByUserIdAndWalletType(userId, "NBFC")
                ?: walletRepo.save(WalletEntity(userId = userId, walletType = "NBFC"))

            // Persist into the EXISTING payment_orders table (V5) --
            // purpose='WALLET_TOPUP' is an allowed value already. referenceId
            // = wallet.id so the webhook handler / sweeper job know which
            // wallet to credit. `receipt` doubles as idempotencyKey here --
            // it's already unique per call (millis-suffixed).
            paymentRepo.save(
                PaymentOrderEntity(
                    userId = userId,
                    razorpayOrderId = order.orderId,     // Cashfree order id (column name is legacy Razorpay-era, see V17 migration note)
                    amountPaise = amountRupees.multiply(BigDecimal(100)).toLong(),
                    purpose = "WALLET_TOPUP",
                    referenceId = wallet.id,
                    idempotencyKey = receipt
                )
            )

            Result.success(
                CreateWalletTopupOrderResponse(
                    orderId = order.orderId,
                    paymentSessionId = order.paymentSessionId,
                    amount = amountRupees.multiply(BigDecimal(100)).toLong(),
                    currency = "INR",
                    receipt = receipt
                )
            )
        } catch (e: CashfreeOrderCreationException) {
            log.error("Topup order creation failed for userId={}: {}", userId, e.message)
            Result.failure(TopupOrderCreationException(e.message ?: "Cashfree error"))
        }
    }

    // ── WalletCreditPort implementation ──
    //
    // Called by PaymentService.handleCashfreeCaptured() (modules/payment)
    // when a payment_orders row with purpose='WALLET_TOPUP' is confirmed
    // CAPTURED via Cashfree webhook. See WalletCreditPort.kt (shared/core)
    // for why this is an interface rather than a direct method call --
    // avoids a circular module dependency between wallet and payment.
    override suspend fun creditWalletTopup(
        userId: UUID,
        walletType: String,
        amountPaise: Long,
        idempotencyKey: String,
        cashfreeOrderId: String
    ): Boolean {
        val wallet = walletRepo.findByUserIdAndWalletType(userId, walletType)
        if (wallet == null) {
            log.error(
                "WALLET_TOPUP webhook: no {} wallet for userId={}, cashfreeOrderId={} -- cannot credit",
                walletType, userId, cashfreeOrderId
            )
            return false
        }

        // credit() itself dedupes on idempotencyKey via ledger lookup, so a
        // webhook retry for the same order is a safe no-op here.
        val amountRupees = BigDecimal(amountPaise).divide(BigDecimal(100))
        val result = credit(
            userId = userId,
            walletType = walletType,
            amount = amountRupees,
            referenceType = "WALLET_TOPUP",
            referenceId = wallet.id,
            description = "Wallet top-up via Cashfree ($cashfreeOrderId)",
            idempotencyKey = idempotencyKey
        )

        return when (result) {
            is Result.Success -> {
                log.info("WALLET_TOPUP credited: userId={}, amount=₹{}, cashfreeOrderId={}", userId, amountRupees, cashfreeOrderId)
                true
            }
            is Result.Failure -> {
                log.error("WALLET_TOPUP credit failed: userId={}, cashfreeOrderId={}, error={}", userId, cashfreeOrderId, result.error.message)
                false
            }
        }
    }

    // ← NAYA: reverseDebit() -- generic refund/reversal, RechargeService use
    // karta hai jab WALLET-paid recharge A1Topup delivery pe fail ho jaye.
    override suspend fun reverseDebit(
        userId: UUID,
        walletType: String,
        amountPaise: Long,
        referenceType: String,
        referenceId: UUID?,
        description: String?,
        idempotencyKey: String
    ): Boolean {
        val amountRupees = BigDecimal(amountPaise).divide(BigDecimal(100))
        val result = credit(
            userId = userId,
            walletType = walletType,
            amount = amountRupees,
            referenceType = referenceType,
            referenceId = referenceId,
            description = description,
            idempotencyKey = idempotencyKey
        )

        return when (result) {
            is Result.Success -> {
                log.info("Wallet reversal credited: userId={}, amount=₹{}, referenceType={}", userId, amountRupees, referenceType)
                true
            }
            is Result.Failure -> {
                log.error("Wallet reversal FAILED: userId={}, referenceType={}, error={}", userId, referenceType, result.error.message)
                false
            }
        }
    }

    // ── WalletDebitPort implementation ──
    //
    // NOT YET CALLED from anywhere -- RechargeService's "pay recharge from
    // wallet" branch is a deferred follow-up (see WalletDebitPort.kt doc
    // comment). This just makes the allowlist+debit logic ready to wire in
    // later without touching the live Cashfree recharge flow now.
    override suspend fun debitForService(
        userId: UUID,
        walletType: String,
        amount: BigDecimal,
        serviceCode: String,
        referenceId: UUID?,
        description: String?,
        idempotencyKey: String
    ): WalletDebitOutcome {
        if (serviceCode !in serviceCodeAllowlist) {
            log.warn("Wallet debit rejected: serviceCode={} not in allowlist, userId={}", serviceCode, userId)
            return WalletDebitOutcome.Rejected(
                WalletDebitRejectionReason.SERVICE_NOT_ALLOWED,
                "Wallet payments are not enabled for $serviceCode yet"
            )
        }

        val result = debit(
            userId = userId,
            walletType = walletType,
            amount = amount,
            referenceType = serviceCode,
            referenceId = referenceId,
            description = description,
            idempotencyKey = idempotencyKey
        )

        return when (result) {
            is Result.Success -> WalletDebitOutcome.Success(result.value.walletId, result.value.balance)
            is Result.Failure -> when (result.error) {
                is InsufficientBalanceException -> WalletDebitOutcome.Rejected(
                    WalletDebitRejectionReason.INSUFFICIENT_BALANCE, result.error.message
                )
                is WalletNotFoundException -> WalletDebitOutcome.Rejected(
                    WalletDebitRejectionReason.WALLET_NOT_FOUND, result.error.message
                )
                else -> WalletDebitOutcome.Rejected(
                    WalletDebitRejectionReason.WALLET_NOT_FOUND, result.error.message
                )
            }
        }
    }

    // ── Wallet Top-up Sweeper (missed-webhook safety net) ──
    //
    // Same convention as RechargeService.reconcilePendingRecharges():
    // scheduled directly on the owning service, filters in-memory by age,
    // per-order try/catch so one bad status check doesn't block the rest
    // of the batch. Give the webhook >= 2 minutes to arrive naturally
    // before polling, give up after ~60 minutes (needs a human by then,
    // not more polling).
    @Scheduled(fixedDelay = 300_000) // every 5 minutes
    suspend fun sweepPendingTopups() {
        val allPending = try {
            listOf("CREATED", "PENDING").flatMap {
                paymentRepo.findByPurposeAndStatus("WALLET_TOPUP", it)
            }
        } catch (e: Exception) {
            log.error("Wallet topup sweeper: failed to fetch pending orders", e)
            return
        }

        if (allPending.isEmpty()) return

        val now = Instant.now()
        val eligible = allPending.filter { order ->
            val ageSinceCreatedMin = Duration.between(order.createdAt, now).toMinutes()
            ageSinceCreatedMin >= 2 && ageSinceCreatedMin < 60
        }

        if (eligible.isEmpty()) return
        log.info("Wallet topup sweeper: checking {} pending order(s)", eligible.size)

        for (order in eligible) {
            try {
                val cfStatus = cashfreeClient.getOrderStatus(order.razorpayOrderId)
                when (cfStatus.orderStatus) {
                    "PAID" -> {
                        if (order.status == "CAPTURED") continue // race with webhook, already handled

                        val updated = paymentRepo.updateWebhookCaptured(
                            id = order.id!!,
                            razorpayPaymentId = null,   // sweeper's order-status poll doesn't return a payment id -- see getOrderStatus() doc comment
                            status = "CAPTURED",
                            webhookEvent = "SWEEPER_RECONCILED",
                            webhookPayload = "{}"
                        )

                        val credited = creditWalletTopup(
                            userId = updated.userId,
                            walletType = "NBFC",
                            amountPaise = updated.amountPaise,
                            idempotencyKey = updated.idempotencyKey,
                            cashfreeOrderId = order.razorpayOrderId
                        )

                        if (credited) {
                            log.info("Wallet topup sweeper: recovered missed webhook, credited orderId={}", order.id)
                        } else {
                            log.error("Wallet topup sweeper: orderId={} marked CAPTURED but credit FAILED -- needs manual review", order.id)
                        }
                    }
                    "EXPIRED", "TERMINATED" -> {
                        paymentRepo.save(order.copy(status = "FAILED", updatedAt = Instant.now()))
                        log.info("Wallet topup sweeper: orderId={} marked FAILED (Cashfree status={})", order.id, cfStatus.orderStatus)
                    }
                    else -> {
                        log.debug("Wallet topup sweeper: orderId={} still {} on Cashfree", order.id, cfStatus.orderStatus)
                    }
                }
            } catch (e: Exception) {
                log.warn("Wallet topup sweeper: status check failed for orderId={} (non-fatal, retry next cycle)", order.id, e)
            }
        }
    }
}