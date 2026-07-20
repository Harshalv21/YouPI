package `in`.youpi.wallet.service

import `in`.youpi.core.BaseException
import `in`.youpi.core.Result
import `in`.youpi.core.razorpay.RazorpayClient
import `in`.youpi.core.razorpay.RazorpayOrderCreationException
import `in`.youpi.core.ratelimit.RateLimiterService
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.core.R2dbcEntityTemplate
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.r2dbc.connection.R2dbcTransactionManager
import org.springframework.stereotype.Service
import org.springframework.transaction.reactive.TransactionalOperator
import org.springframework.transaction.reactive.executeAndAwait
import java.math.BigDecimal
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

// ← User lookup for recipient resolution
interface UserLookupRepository : CoroutineCrudRepository<UserLookupEntity, UUID> {
    suspend fun findByMobile(mobile: String): UserLookupEntity?
}

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

data class TransferRequest(
    val recipientMobile: String,
    val amount: BigDecimal,
    val walletType: String = "NBFC",
    val description: String? = null,
    val idempotencyKey: String
)

data class TransferResponse(
    val message: String,
    val senderBalance: WalletInfo,
    val recipientBalance: WalletInfo      // ← ab recipient bhi return hoga
)

// ← NAYA: wallet topup order DTOs
data class CreateWalletTopupOrderRequest(
    val amountRupees: BigDecimal
)

data class CreateWalletTopupOrderResponse(
    val orderId: String,
    val amount: Long,       // paise
    val currency: String,
    val receipt: String?,
    val keyId: String
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

class RecipientNotFoundException(mobile: String) : WalletException(
    "RECIPIENT_NOT_FOUND", "No user found with mobile $mobile", 404
)
class SelfTransferException : WalletException(
    "SELF_TRANSFER",
    "Cannot transfer to yourself",
    400
)

// ← NAYA: topup order creation exception
class TopupOrderCreationException(reason: String) : WalletException(
    "TOPUP_ORDER_FAILED", "Unable to create topup order: $reason", 502
)

class TopupRateLimitExceededException : WalletException(
    "TOPUP_RATE_LIMIT_EXCEEDED", "Too many topup attempts, please try again in a minute", 429
)

@Service
class WalletService(
    private val walletRepo: WalletRepository,
    private val ledgerRepo: LedgerEntryRepository,
    private val userLookupRepo: UserLookupRepository,            // ← naya
    private val txManager: R2dbcTransactionManager,               // ← @Transactional replace
    private val razorpayClient: RazorpayClient,                          // ← NAYA
    @Value("\${youpi.razorpay.key-id:}") private val razorpayKeyId: String,  // ← NAYA
    private val rateLimiterService: RateLimiterService                    // ← NAYA (rate limit)
) {
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

    // ← Yeh ab complete P2P transfer karta hai — debit + credit dono ek transaction mein
    suspend fun transfer(
    senderId: UUID,
    req: TransferRequest
): Result<TransferResponse, WalletException> {

    println(">>> transfer() method called <<<")

    if (req.amount <= BigDecimal.ZERO) {
    
            return Result.failure(InsufficientBalanceException(BigDecimal.ZERO, req.amount))
        }

        // Recipient user dhundo
        val normalizedMobile = "+91${req.recipientMobile.takeLast(10)}"
        val recipientUser = userLookupRepo.findByMobile(normalizedMobile)
            ?: return Result.failure(RecipientNotFoundException(normalizedMobile))

        val recipientId = recipientUser.id!!

        // Self-transfer block karo

log.info("SenderId = {}", senderId)
log.info("RecipientId = {}", recipientId)
log.info("RecipientMobile = {}", normalizedMobile)

// Self-transfer block karo
if (senderId == recipientId) {
    log.info("SELF TRANSFER DETECTED")
    return Result.failure(SelfTransferException())
}

        return txOperator.executeAndAwait {
            // Sender debit
            val debitResult = debit(
                userId = senderId,
                walletType = req.walletType,
                amount = req.amount,
                referenceType = "P2P_SEND",
                description = req.description ?: "P2P transfer to $normalizedMobile",
                idempotencyKey = "${req.idempotencyKey}_debit"
            )
            if (debitResult is Result.Failure) return@executeAndAwait debitResult

            // Recipient wallet ensure karo (lazily create karo agar nahi hai)
            val recipientWallet = walletRepo.findByUserIdAndWalletType(recipientId, req.walletType)
                ?: walletRepo.save(WalletEntity(userId = recipientId, walletType = req.walletType))

            // Recipient credit
            val creditResult = credit(
                userId = recipientId,
                walletType = req.walletType,
                amount = req.amount,
                referenceType = "P2P_RECEIVE",
                description = "P2P transfer from sender",
                idempotencyKey = "${req.idempotencyKey}_credit"
            )
            if (creditResult is Result.Failure) return@executeAndAwait creditResult

            Result.success(TransferResponse(
                message = "Transfer successful",
                senderBalance = (debitResult as Result.Success).value,
                recipientBalance = (creditResult as Result.Success).value
            ))
        }!!
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

    // ← NAYA: Wallet topup ke liye Razorpay order create karta hai
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

        val amountPaise = amountRupees.multiply(BigDecimal(100)).toLong()
        val shortUserId = userId.toString().take(8)
        val receipt = "wtop_${shortUserId}_${System.currentTimeMillis()}"

        return try {
            val order = razorpayClient.createOrder(
                amountPaise = amountPaise,
                receipt = receipt,
                notes = mapOf(
                    "module" to "wallet_topup",
                    "userId" to userId.toString()
                )
            )

            log.info("Topup order created: userId={}, orderId={}, amount=₹{}", userId, order.id, amountRupees)

            // TODO: persist order in DB (payment_orders table) once table is decided

            Result.success(
                CreateWalletTopupOrderResponse(
                    orderId = order.id,
                    amount = order.amount,
                    currency = order.currency,
                    receipt = order.receipt,
                    keyId = razorpayKeyId
                )
            )
        } catch (e: RazorpayOrderCreationException) {
            log.error("Topup order creation failed for userId={}: {}", userId, e.message)
            Result.failure(TopupOrderCreationException(e.message ?: "Razorpay error"))
        }
    }
}