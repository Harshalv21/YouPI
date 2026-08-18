package `in`.youpi.wallet.service

import `in`.youpi.core.BaseException
import `in`.youpi.core.Result
import `in`.youpi.core.WalletCreditPort
import `in`.youpi.core.WalletDebitOutcome
import `in`.youpi.core.WalletDebitPort
import `in`.youpi.core.WalletDebitRejectionReason
import `in`.youpi.core.razorpay.RazorpayClient
import `in`.youpi.core.razorpay.RazorpayOrderCreationException
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

// ── Entities ── -- UNCHANGED, no gateway involvement

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

    @Query("UPDATE wallets SET balance = balance + :amount, updated_at = NOW() WHERE id = :id AND balance + :amount >= 0 RETURNING id")
    suspend fun atomicBalanceUpdate(id: UUID, amount: BigDecimal): UUID?
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

data class CreateWalletTopupOrderRequest(
    @field:jakarta.validation.constraints.Positive(message = "amountRupees must be positive")
    val amountRupees: BigDecimal
)

// REVERTED: paymentSessionId is now always null (Cashfree-only concept).
// razorpayKeyId added -- Flutter's Razorpay checkout SDK needs this to
// open the checkout sheet, same pattern as PaymentOrderResponse/
// RechargeOrderResponse elsewhere in this migration.
data class CreateWalletTopupOrderResponse(
    val orderId: String,
    val paymentSessionId: String? = null,
    val razorpayKeyId: String? = null,
    val amount: Long,       // paise
    val currency: String,
    val receipt: String?
)

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
    private val userLookupRepo: UserLookupRepository,
    private val txManager: R2dbcTransactionManager,
    // REVERTED from CashfreeClient back to RazorpayClient. See
    // createTopupOrder() and sweepPendingTopups() below for the concrete
    // API differences this swap requires.
    private val razorpayClient: RazorpayClient,
    private val rateLimiterService: RateLimiterService,
    private val paymentRepo: PaymentOrderRepository,
    // NEW: Razorpay checkout SDK needs key_id client-side to open the
    // checkout sheet -- Cashfree's flow didn't expose a key like this.
    @Value("\${youpi.razorpay.key-id:}") private val razorpayKeyId: String
) : WalletCreditPort, WalletDebitPort {

    private val serviceCodeAllowlist = setOf("RECHARGE")
    private val log = LoggerFactory.getLogger(javaClass)
    private val txOperator = TransactionalOperator.create(txManager)

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

        return txOperator.executeAndAwait {
            val balanceBefore = wallet.balance
            val updatedId = walletRepo.atomicBalanceUpdate(wallet.id!!, amount)
            if (updatedId == null) return@executeAndAwait Result.failure(WalletNotFoundException(userId, walletType))
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

        return txOperator.executeAndAwait {
            val balanceBefore = wallet.balance
            val updatedId = walletRepo.atomicBalanceUpdate(wallet.id!!, amount.negate())
            if (updatedId == null) return@executeAndAwait Result.failure(InsufficientBalanceException(wallet.balance, amount))
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

    // ← razorpayOrderId param name kept as cashfreeOrderId's DB column
    // equivalent -- getTopupOrderStatus() reads via findByRazorpayOrderId,
    // which is unaffected by this revert (column was always razorpay-named).
    suspend fun getTopupOrderStatus(userId: UUID, razorpayOrderId: String): Result<WalletTopupStatusResponse, WalletException> {
        val order = paymentRepo.findByRazorpayOrderId(razorpayOrderId)
            ?: return Result.failure(TopupOrderNotFoundException(razorpayOrderId))

        if (order.userId != userId || order.purpose != "WALLET_TOPUP") {
            return Result.failure(TopupOrderNotFoundException(razorpayOrderId))
        }

        return Result.success(
            WalletTopupStatusResponse(
                orderId = razorpayOrderId,
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

    // ← REVERTED to RazorpayClient. Two concrete differences from the
    // Cashfree version this replaces:
    //   1. Amount unit: paise (Long), not rupees (Double).
    //   2. No customerPhone needed -- Razorpay's create-order call doesn't
    //      require it, so the userMobile lookup (and its failure path) is
    //      removed entirely.
    suspend fun createTopupOrder(
        userId: UUID,
        amountRupees: BigDecimal
    ): Result<CreateWalletTopupOrderResponse, WalletException> {

        if (amountRupees <= BigDecimal.ZERO) {
            return Result.failure(TopupOrderCreationException("Amount must be greater than zero"))
        }

        val rateLimitKey = "rl:wallet:topup:$userId"
        val allowed = rateLimiterService.isAllowed(rateLimitKey, limit = 5, windowSeconds = 60)
        if (!allowed) {
            log.warn("Rate limit exceeded for wallet topup: userId={}", userId)
            return Result.failure(TopupRateLimitExceededException())
        }

        val shortUserId = userId.toString().take(8)
        val receipt = "wtop_${shortUserId}_${System.currentTimeMillis()}"
        val amountPaise = amountRupees.multiply(BigDecimal(100)).toLong()

        return try {
            val order = razorpayClient.createOrder(
                amountPaise = amountPaise,
                receipt = receipt,
                notes = mapOf("purpose" to "WALLET_TOPUP", "userId" to userId.toString())
            )

            log.info("Topup order created: userId={}, orderId={}, amount=₹{}", userId, order.id, amountRupees)

            val wallet = walletRepo.findByUserIdAndWalletType(userId, "NBFC")
                ?: walletRepo.save(WalletEntity(userId = userId, walletType = "NBFC"))

            paymentRepo.save(
                PaymentOrderEntity(
                    userId = userId,
                    razorpayOrderId = order.id,
                    amountPaise = amountPaise,
                    purpose = "WALLET_TOPUP",
                    referenceId = wallet.id,
                    idempotencyKey = receipt
                )
            )

            Result.success(
                CreateWalletTopupOrderResponse(
                    orderId = order.id,
                    paymentSessionId = null,
                    razorpayKeyId = razorpayKeyId,
                    amount = amountPaise,
                    currency = "INR",
                    receipt = receipt
                )
            )
        } catch (e: RazorpayOrderCreationException) {
            log.error("Topup order creation failed for userId={}: {}", userId, e.message)
            Result.failure(TopupOrderCreationException(e.message ?: "Razorpay error"))
        }
    }

    // ── WalletCreditPort implementation ──
    //
    // Called by PaymentService's Razorpay webhook handler when a
    // payment_orders row with purpose='WALLET_TOPUP' is confirmed CAPTURED.
    // Parameter is still named cashfreeOrderId (interface contract,
    // shared/core/WalletCreditPort.kt) -- it's just a gateway order-id
    // reference field, works the same with a Razorpay order_id value.
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
                "WALLET_TOPUP webhook: no {} wallet for userId={}, orderId={} -- cannot credit",
                walletType, userId, cashfreeOrderId
            )
            return false
        }

        val amountRupees = BigDecimal(amountPaise).divide(BigDecimal(100))
        val result = credit(
            userId = userId,
            walletType = walletType,
            amount = amountRupees,
            referenceType = "WALLET_TOPUP",
            referenceId = wallet.id,
            description = "Wallet top-up via Razorpay ($cashfreeOrderId)",
            idempotencyKey = idempotencyKey
        )

        return when (result) {
            is Result.Success -> {
                log.info("WALLET_TOPUP credited: userId={}, amount=₹{}, orderId={}", userId, amountRupees, cashfreeOrderId)
                true
            }
            is Result.Failure -> {
                log.error("WALLET_TOPUP credit failed: userId={}, orderId={}, error={}", userId, cashfreeOrderId, result.error.message)
                false
            }
        }
    }

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
    // REVERTED to RazorpayClient.fetchOrder(). Key difference from the
    // Cashfree version: Razorpay's order.status vocabulary is "created" /
    // "attempted" / "paid" -- there's no "EXPIRED"/"TERMINATED" terminal
    // state to branch on, so that failure-marking branch is dropped; a
    // Razorpay order that never gets paid just ages out via the existing
    // 60-minute eligibility cutoff below (unchanged) rather than being
    // explicitly marked FAILED by this sweeper. Also: fetchOrder() alone
    // doesn't return a payment id, so fetchFirstPaymentId() is called
    // separately once status="paid" is confirmed.
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
                val rzOrder = razorpayClient.fetchOrder(order.razorpayOrderId)
                when (rzOrder.status) {
                    "paid" -> {
                        if (order.status == "CAPTURED") continue // race with webhook, already handled

                        val paymentId = razorpayClient.fetchFirstPaymentId(order.razorpayOrderId)

                        val updated = paymentRepo.updateWebhookCaptured(
                            id = order.id!!,
                            razorpayPaymentId = paymentId,
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
                    else -> {
                        log.debug("Wallet topup sweeper: orderId={} still {} on Razorpay", order.id, rzOrder.status)
                    }
                }
            } catch (e: Exception) {
                log.warn("Wallet topup sweeper: status check failed for orderId={} (non-fatal, retry next cycle)", order.id, e)
            }
        }
    }
}