package `in`.youpi.invest.service

import `in`.youpi.core.BaseException
import `in`.youpi.core.ExternalServiceException
import `in`.youpi.core.NotFoundException
import `in`.youpi.core.Result
import `in`.youpi.invest.augmont.*
import org.slf4j.LoggerFactory
import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.stereotype.Service
import kotlinx.coroutines.reactive.awaitFirstOrNull
import kotlinx.coroutines.reactive.awaitSingle
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

// ── Entities ──

@Table("gold_holdings")
data class GoldHoldingEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val totalGrams: BigDecimal = BigDecimal.ZERO,
    val totalInvested: BigDecimal = BigDecimal.ZERO,
    val goldProvider: String = "AUGMONT",
    val providerUserId: String? = null,
    val updatedAt: Instant = Instant.now()
)

interface GoldHoldingRepository : CoroutineCrudRepository<GoldHoldingEntity, UUID> {
    suspend fun findByUserId(userId: UUID): GoldHoldingEntity?
}

@Table("gold_transactions")
data class GoldTransactionEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val txnType: String,
    val amountInr: BigDecimal,
    val grams: BigDecimal,
    val ratePerGram: BigDecimal,
    val providerTxnId: String? = null,
    val augmontTxnId: String? = null,
    val blockId: String? = null,
    val metalType: String = "GOLD",
    val status: String = "PENDING",
    val triggeredBy: String,
    val rechargeOrderId: UUID? = null,
    val idempotencyKey: String,
    val createdAt: Instant = Instant.now()
)

interface GoldTransactionRepository : CoroutineCrudRepository<GoldTransactionEntity, UUID> {
    suspend fun findByIdempotencyKey(idempotencyKey: String): GoldTransactionEntity?

    @Query("SELECT * FROM gold_transactions WHERE user_id = :userId ORDER BY created_at DESC LIMIT :limit")
    suspend fun findByUserId(userId: UUID, limit: Int = 20): List<GoldTransactionEntity>
}

@Table("fixed_deposits")
data class FixedDepositEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val principal: BigDecimal,
    val interestRate: BigDecimal,
    val tenureMonths: Short,
    val maturityDate: LocalDate,
    val maturityAmount: BigDecimal,
    val bankPartner: String = "AXIS_BANK",
    val bankFdRef: String? = null,
    val status: String = "ACTIVE",
    val createdAt: Instant = Instant.now()
)

interface FixedDepositRepository : CoroutineCrudRepository<FixedDepositEntity, UUID> {
    suspend fun findAllByUserId(userId: UUID): List<FixedDepositEntity>
}

@Table("augmont_user_mappings")
data class AugmontUserMappingEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val augmontUniqueId: String,
    val augmontUserName: String? = null,
    val kycStatus: String = "PENDING",
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface AugmontUserMappingRepository : CoroutineCrudRepository<AugmontUserMappingEntity, UUID> {
    suspend fun findByUserId(userId: UUID): AugmontUserMappingEntity?
    suspend fun findByAugmontUniqueId(augmontUniqueId: String): AugmontUserMappingEntity?
}

// ── Response DTOs ──

data class GoldPriceResponse(
    val goldBuyRate: BigDecimal,
    val goldSellRate: BigDecimal,
    val silverBuyRate: BigDecimal,
    val silverSellRate: BigDecimal,
    val blockId: String,
    val provider: String = "Augmont",
    val cachedAt: Instant
)

data class GoldHoldingResponse(
    val userId: UUID,
    val totalGrams: BigDecimal,
    val totalInvested: BigDecimal,
    val currentValue: BigDecimal
)

data class GoldBuyResponse(
    val txnId: UUID,
    val augmontTxnId: String?,
    val amountInr: BigDecimal,
    val grams: BigDecimal,
    val status: String
)

data class GoldSellResponse(
    val txnId: UUID,
    val augmontTxnId: String?,
    val grams: BigDecimal,
    val amountInr: BigDecimal,
    val status: String
)

data class PassbookResponse(
    val goldGrams: BigDecimal,
    val silverGrams: BigDecimal,
    val goldBalance: BigDecimal,
    val silverBalance: BigDecimal
)

// ── Sealed Exceptions ──

sealed class GoldException(code: String, message: String, httpStatus: Int = 400)
    : BaseException(code, message) {
    override val httpStatus: Int = httpStatus
}

class GoldRateStaledException : GoldException("GOLD_RATE_UNAVAILABLE", "Gold rate data is stale or unavailable.", 503)
class GoldProviderException(reason: String) : GoldException("GOLD_PROVIDER_ERROR", "Gold provider error: $reason", 502)
class AugmontUserNotMappedException : GoldException("AUGMONT_USER_NOT_MAPPED", "User has no Augmont account. Please create one first.", 400)

/**
 * Invest service — Digital Gold/Silver via Augmont Merchant API + Fixed Deposits.
 * Gold/Silver rates cached in Redis with 35s TTL (Augmont enforces 10 calls/min on rates).
 */
@Service
class InvestService(
    private val goldHoldingRepo: GoldHoldingRepository,
    private val goldTxnRepo: GoldTransactionRepository,
    private val fdRepo: FixedDepositRepository,
    private val augmontUserRepo: AugmontUserMappingRepository,
    private val augmontClient: AugmontClient,
    private val redisTemplate: ReactiveStringRedisTemplate
) {

    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        private const val RATES_CACHE_KEY = "augmont:rates"
        private const val RATES_BLOCK_KEY = "augmont:rates:blockId"
        private val RATES_TTL = Duration.ofSeconds(35)
    }

    // ══════════════════════════════════════
    // Live Gold/Silver Rates
    // ══════════════════════════════════════

    suspend fun getLiveRates(): Result<GoldPriceResponse, GoldException> {
        // Try Redis cache
        val ops = redisTemplate.opsForHash<String, String>()
        val cached = ops.entries(RATES_CACHE_KEY).collectList().awaitSingle()
        val cachedMap = cached.associate { it.key to it.value }

        if (cachedMap.isNotEmpty() && cachedMap["goldBuy"] != null) {
            return Result.success(GoldPriceResponse(
                goldBuyRate = BigDecimal(cachedMap["goldBuy"]),
                goldSellRate = BigDecimal(cachedMap["goldSell"] ?: "0"),
                silverBuyRate = BigDecimal(cachedMap["silverBuy"] ?: "0"),
                silverSellRate = BigDecimal(cachedMap["silverSell"] ?: "0"),
                blockId = cachedMap["blockId"] ?: "",
                cachedAt = Instant.now()
            ))
        }

        // Fetch live from Augmont
        return try {
            val response = augmontClient.getRates()
            val data = response.result?.data
                ?: return Result.failure(GoldRateStaledException())

            val goldBuy = data.goldBuy ?: return Result.failure(GoldRateStaledException())
            val blockId = data.blockId ?: ""

            // Cache rates in Redis hash
            val rateMap = mapOf(
                "goldBuy" to goldBuy.toPlainString(),
                "goldSell" to (data.goldSell ?: BigDecimal.ZERO).toPlainString(),
                "silverBuy" to (data.silverBuy ?: BigDecimal.ZERO).toPlainString(),
                "silverSell" to (data.silverSell ?: BigDecimal.ZERO).toPlainString(),
                "blockId" to blockId,
                "gst" to (data.gst ?: BigDecimal.ZERO).toPlainString()
            )
            ops.putAll(RATES_CACHE_KEY, rateMap).awaitSingle()
            redisTemplate.expire(RATES_CACHE_KEY, RATES_TTL).awaitSingle()

            Result.success(GoldPriceResponse(
                goldBuyRate = goldBuy,
                goldSellRate = data.goldSell ?: BigDecimal.ZERO,
                silverBuyRate = data.silverBuy ?: BigDecimal.ZERO,
                silverSellRate = data.silverSell ?: BigDecimal.ZERO,
                blockId = blockId,
                cachedAt = Instant.now()
            ))
        } catch (ex: Exception) {
            log.error("Augmont: Failed to fetch rates", ex)
            Result.failure(GoldRateStaledException())
        }
    }

    // backward compat: old getLiveGoldPrice returns buy rate only
    suspend fun getLiveGoldPrice(): Result<GoldPriceResponse, GoldException> = getLiveRates()

    // ══════════════════════════════════════
    // Augmont User Management
    // ══════════════════════════════════════

    /**
     * Ensures the YouPI user has an Augmont user mapping.
     * Returns the Augmont uniqueId.
     */
    suspend fun ensureAugmontUser(
        userId: UUID,
        userName: String,
        userEmail: String,
        userMobile: String
    ): String {
        // Check local mapping
        val existing = augmontUserRepo.findByUserId(userId)
        if (existing != null) return existing.augmontUniqueId

        // Create on Augmont
        val response = augmontClient.createUser(AugmontCreateUserRequest(
            userName = userName,
            userEmail = userEmail,
            userMobile = userMobile
        ))

        val uniqueId = response.result?.data?.uniqueId
            ?: throw ExternalServiceException("Augmont", "User creation failed: ${response.message}")

        // Save mapping
        augmontUserRepo.save(AugmontUserMappingEntity(
            userId = userId,
            augmontUniqueId = uniqueId,
            augmontUserName = userName
        ))

        log.info("Augmont: Created user mapping userId={} → augmontId={}", userId, uniqueId)
        return uniqueId
    }

    /**
     * Gets the Augmont uniqueId for an existing user. Throws if not mapped.
     */
    private suspend fun getAugmontUniqueId(userId: UUID): String {
        return augmontUserRepo.findByUserId(userId)?.augmontUniqueId
            ?: throw AugmontUserNotMappedException()
    }

    // ══════════════════════════════════════
    // Gold Buy
    // ══════════════════════════════════════

    suspend fun buyGold(
        userId: UUID,
        amountInr: BigDecimal,
        idempotencyKey: String,
        triggeredBy: String = "MANUAL",
        metalType: String = "gold"
    ): Result<GoldBuyResponse, GoldException> {

        // Idempotency
        val existing = goldTxnRepo.findByIdempotencyKey(idempotencyKey)
        if (existing != null) {
            return Result.success(GoldBuyResponse(existing.id!!, existing.augmontTxnId, existing.amountInr, existing.grams, existing.status))
        }

        // Get rates with blockId
        val ratesResult = getLiveRates()
        if (ratesResult.isFailure) return Result.failure(GoldRateStaledException())
        val rates = ratesResult.getOrNull()!!

        val buyRate = if (metalType == "silver") rates.silverBuyRate else rates.goldBuyRate
        val grams = amountInr.divide(buyRate, 6, java.math.RoundingMode.FLOOR)

        // Get Augmont user
        val augmontUniqueId = getAugmontUniqueId(userId)
        val merchantTxnId = "YOUPI-BUY-${UUID.randomUUID()}"

        // Save PENDING transaction first
        val txn = goldTxnRepo.save(GoldTransactionEntity(
            userId = userId,
            txnType = "BUY",
            amountInr = amountInr,
            grams = grams,
            ratePerGram = buyRate,
            blockId = rates.blockId,
            metalType = metalType.uppercase(),
            status = "PENDING",
            triggeredBy = triggeredBy,
            idempotencyKey = idempotencyKey
        ))

        // Call Augmont buy API
        return try {
            val buyResponse = augmontClient.buy(AugmontBuyRequest(
                lockPrice = buyRate,
                metalType = metalType,
                amount = amountInr,
                blockId = rates.blockId,
                uniqueId = augmontUniqueId,
                merchantTransactionId = merchantTxnId
            ))

            val buyData = buyResponse.result?.data
            val augmontTxnId = buyData?.transactionId
            val actualGrams = buyData?.quantity ?: grams
            val status = if (buyData?.transactionStatus == "success") "SUCCESS" else "PENDING"

            // Update transaction with Augmont response
            goldTxnRepo.save(txn.copy(
                augmontTxnId = augmontTxnId,
                grams = actualGrams,
                status = status
            ))

            // Update local holdings on success
            if (status == "SUCCESS") {
                updateLocalHoldings(userId, actualGrams, amountInr, isAdd = true)
            }

            log.info("Gold bought: userId={}, ₹{} = {}g at ₹{}/g [augmontTxn={}]",
                userId, amountInr, actualGrams, buyRate, augmontTxnId)

            Result.success(GoldBuyResponse(txn.id!!, augmontTxnId, amountInr, actualGrams, status))
        } catch (ex: Exception) {
            log.error("Augmont buy failed for userId={}: {}", userId, ex.message, ex)
            goldTxnRepo.save(txn.copy(status = "FAILED"))
            Result.failure(GoldProviderException(ex.message ?: "Buy failed"))
        }
    }

    // ══════════════════════════════════════
    // Gold Sell
    // ══════════════════════════════════════

    suspend fun sellGold(
        userId: UUID,
        grams: BigDecimal,
        idempotencyKey: String,
        metalType: String = "gold",
        bankAccountId: String? = null
    ): Result<GoldSellResponse, GoldException> {

        // Idempotency
        val existing = goldTxnRepo.findByIdempotencyKey(idempotencyKey)
        if (existing != null) {
            return Result.success(GoldSellResponse(existing.id!!, existing.augmontTxnId, existing.grams, existing.amountInr, existing.status))
        }

        // Get rates
        val ratesResult = getLiveRates()
        if (ratesResult.isFailure) return Result.failure(GoldRateStaledException())
        val rates = ratesResult.getOrNull()!!

        val sellRate = if (metalType == "silver") rates.silverSellRate else rates.goldSellRate
        val amountInr = grams.multiply(sellRate).setScale(2, java.math.RoundingMode.HALF_EVEN)

        // Get Augmont user
        val augmontUniqueId = getAugmontUniqueId(userId)
        val merchantTxnId = "YOUPI-SELL-${UUID.randomUUID()}"

        // Save PENDING transaction
        val txn = goldTxnRepo.save(GoldTransactionEntity(
            userId = userId,
            txnType = "SELL",
            amountInr = amountInr,
            grams = grams,
            ratePerGram = sellRate,
            blockId = rates.blockId,
            metalType = metalType.uppercase(),
            status = "PENDING",
            triggeredBy = "MANUAL",
            idempotencyKey = idempotencyKey
        ))

        return try {
            val sellResponse = augmontClient.sell(AugmontSellRequest(
                lockPrice = sellRate,
                metalType = metalType,
                quantity = grams,
                blockId = rates.blockId,
                uniqueId = augmontUniqueId,
                merchantTransactionId = merchantTxnId,
                bankAccountId = bankAccountId
            ))

            val sellData = sellResponse.result?.data
            val augmontTxnId = sellData?.transactionId
            val actualAmount = sellData?.totalAmount ?: amountInr
            val status = if (sellData?.transactionStatus == "success") "SUCCESS" else "PENDING"

            goldTxnRepo.save(txn.copy(
                augmontTxnId = augmontTxnId,
                amountInr = actualAmount,
                status = status
            ))

            if (status == "SUCCESS") {
                updateLocalHoldings(userId, grams, actualAmount, isAdd = false)
            }

            log.info("Gold sold: userId={}, {}g = ₹{} at ₹{}/g [augmontTxn={}]",
                userId, grams, actualAmount, sellRate, augmontTxnId)

            Result.success(GoldSellResponse(txn.id!!, augmontTxnId, grams, actualAmount, status))
        } catch (ex: Exception) {
            log.error("Augmont sell failed for userId={}: {}", userId, ex.message, ex)
            goldTxnRepo.save(txn.copy(status = "FAILED"))
            Result.failure(GoldProviderException(ex.message ?: "Sell failed"))
        }
    }

    // ══════════════════════════════════════
    // Holdings
    // ══════════════════════════════════════

    private suspend fun updateLocalHoldings(userId: UUID, grams: BigDecimal, amountInr: BigDecimal, isAdd: Boolean) {
        val holding = goldHoldingRepo.findByUserId(userId)
        if (holding != null) {
            val newGrams = if (isAdd) holding.totalGrams.add(grams) else holding.totalGrams.subtract(grams)
            val newInvested = if (isAdd) holding.totalInvested.add(amountInr) else holding.totalInvested.subtract(amountInr)
            goldHoldingRepo.save(holding.copy(
                totalGrams = newGrams.max(BigDecimal.ZERO),
                totalInvested = newInvested.max(BigDecimal.ZERO),
                updatedAt = Instant.now()
            ))
        } else if (isAdd) {
            goldHoldingRepo.save(GoldHoldingEntity(
                userId = userId,
                totalGrams = grams,
                totalInvested = amountInr
            ))
        }
    }

    suspend fun getHoldings(userId: UUID): GoldHoldingResponse {
        val holding = goldHoldingRepo.findByUserId(userId)
            ?: return GoldHoldingResponse(userId, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO)

        val currentRate = getLiveRates().getOrNull()?.goldBuyRate ?: BigDecimal.ZERO
        val currentValue = holding.totalGrams.multiply(currentRate).setScale(2, java.math.RoundingMode.HALF_EVEN)

        return GoldHoldingResponse(
            userId = userId,
            totalGrams = holding.totalGrams,
            totalInvested = holding.totalInvested,
            currentValue = currentValue
        )
    }

    // ══════════════════════════════════════
    // Passbook (from Augmont)
    // ══════════════════════════════════════

    suspend fun getPassbook(userId: UUID): PassbookResponse {
        val uniqueId = getAugmontUniqueId(userId)
        val response = augmontClient.getPassbook(uniqueId)
        val data = response.result?.data

        return PassbookResponse(
            goldGrams = data?.goldGrms ?: BigDecimal.ZERO,
            silverGrams = data?.silverGrms ?: BigDecimal.ZERO,
            goldBalance = data?.goldBalance ?: BigDecimal.ZERO,
            silverBalance = data?.silverBalance ?: BigDecimal.ZERO
        )
    }

    // ══════════════════════════════════════
    // Price History
    // ══════════════════════════════════════

    suspend fun getPriceHistory(metalType: String = "gold", duration: String = "1m"): List<AugmontPricePoint> {
        val response = augmontClient.getRollingData(metalType, duration)
        return response.result?.data ?: emptyList()
    }

    // ══════════════════════════════════════
    // Products (Physical redemption)
    // ══════════════════════════════════════

    suspend fun getProducts(): List<AugmontProduct> {
        val response = augmontClient.getProducts()
        return response.result?.data ?: emptyList()
    }

    // ══════════════════════════════════════
    // Gold FD (Augmont)
    // ══════════════════════════════════════

    suspend fun getGoldFdSchemes(): List<AugmontFdScheme> {
        val response = augmontClient.getFdSchemes()
        return response.result?.data ?: emptyList()
    }

    suspend fun previewGoldFd(goldWeight: BigDecimal, tenure: Int, schemeId: String): AugmontFdPreOrderData? {
        val response = augmontClient.fdPreOrder(AugmontFdPreOrderRequest(goldWeight, tenure, schemeId))
        return response.result?.data
    }

    suspend fun createGoldFd(userId: UUID, goldWeight: BigDecimal, tenure: Int, schemeId: String): AugmontFdOrder? {
        val uniqueId = getAugmontUniqueId(userId)
        val merchantTxnId = "YOUPI-FD-${UUID.randomUUID()}"

        val response = augmontClient.createFd(AugmontFdCreateRequest(
            goldWeight = goldWeight,
            tenure = tenure,
            schemeId = schemeId,
            uniqueId = uniqueId,
            merchantTransactionId = merchantTxnId
        ))

        return response.result?.data
    }

    suspend fun getGoldFdDetail(fdId: String): AugmontFdOrder? {
        val response = augmontClient.getFdDetail(fdId)
        return response.result?.data
    }

    suspend fun closeGoldFd(userId: UUID, fdOrderId: String): AugmontFdPreCloseData? {
        val uniqueId = getAugmontUniqueId(userId)
        val response = augmontClient.preCloseFd(AugmontFdPreCloseRequest(fdOrderId, uniqueId))
        return response.result?.data
    }

    // ══════════════════════════════════════
    // KYC
    // ══════════════════════════════════════

    suspend fun getKycStatus(userId: UUID): AugmontKycData? {
        val uniqueId = getAugmontUniqueId(userId)
        val response = augmontClient.getKycStatus(uniqueId)
        return response.result?.data
    }

    // ══════════════════════════════════════
    // Transaction History
    // ══════════════════════════════════════

    suspend fun getTransactions(userId: UUID, limit: Int = 20): List<GoldTransactionEntity> =
        goldTxnRepo.findByUserId(userId, limit)

    // ── Fixed Deposits (legacy bank FDs) ──

    suspend fun getFds(userId: UUID): List<FixedDepositEntity> = fdRepo.findAllByUserId(userId)
}
