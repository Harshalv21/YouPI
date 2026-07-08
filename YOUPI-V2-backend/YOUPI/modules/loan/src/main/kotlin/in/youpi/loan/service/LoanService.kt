package `in`.youpi.loan.service

import `in`.youpi.core.BaseException
import `in`.youpi.core.Result
import `in`.youpi.events.PubSubPublisher
import kotlinx.coroutines.reactor.awaitSingle
import kotlinx.coroutines.reactor.awaitSingleOrNull
import org.slf4j.LoggerFactory
import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import kotlin.math.pow
import java.util.UUID

// =======================================================
// Loan Application
// =======================================================

@Table("loan_applications")
data class LoanApplicationEntity(

    @Id
    val id: UUID? = null,

    val userId: UUID,

    val fullName: String,

    val dateOfBirth: LocalDate,

    val panNumber: String,

    val panGcsPath: String? = null,

    val fathersName: String? = null,

    val address: String? = null,

    val pincode: String? = null,

    val city: String? = null,

    val state: String? = null,

    val aadhaarLast4: String? = null,

    val aadhaarFrontGcs: String? = null,

    val aadhaarBackGcs: String? = null,

    val employmentType: String? = null,

    val employerName: String? = null,

    val workEmail: String? = null,

    val monthlyIncome: BigDecimal? = null,

    val annualTurnover: BigDecimal? = null,

    val yearsExperience: String? = null,

    val cibilScore: Short? = null,

    val cibilConsent: Boolean = false,

    val requestedAmount: BigDecimal? = null,

    val approvedAmount: BigDecimal? = null,

    val interestRate: BigDecimal? = null,

    val tenureMonths: Short? = null,

    val status: String = "SUBMITTED",

    val rejectionReason: String? = null,

    val reviewedBy: UUID? = null,

    val reviewedAt: Instant? = null,

    val createdAt: Instant = Instant.now(),

    val updatedAt: Instant = Instant.now()
)

interface LoanApplicationRepository :
    CoroutineCrudRepository<LoanApplicationEntity, UUID> {

    @Query(
        """
        SELECT *
        FROM loan_applications
        WHERE user_id = :userId
        ORDER BY created_at DESC
        LIMIT 1
        """
    )
    suspend fun findLatestByUserId(userId: UUID): LoanApplicationEntity?

    suspend fun findAllByStatus(status: String): List<LoanApplicationEntity>
}

// =======================================================
// Loan Account
// =======================================================

@Table("loan_accounts")
data class LoanAccountEntity(

    @Id
    val id: UUID? = null,

    val userId: UUID,

    val applicationId: UUID,

    val principal: BigDecimal,

    val interestRate: BigDecimal,

    val tenureMonths: Short,

    val monthlyEmi: BigDecimal,

    val outstandingBalance: BigDecimal,

    val bankPartner: String = "AXIS_BANK",

    val bankLoanRef: String? = null,

    val enachStatus: String = "PENDING",

    val enachMandateId: String? = null,

    val disbursedAt: Instant? = null,

    val status: String = "ACTIVE",

    val createdAt: Instant = Instant.now(),

    val updatedAt: Instant = Instant.now()
)

interface LoanAccountRepository :
    CoroutineCrudRepository<LoanAccountEntity, UUID> {

    suspend fun findByUserId(userId: UUID): LoanAccountEntity?
}
//...................
// =======================================================
// Loan EMI Schedule
// =======================================================

@Table("loan_emi_schedule")
data class LoanEmiEntity(

    @Id
    val id: UUID? = null,

    val loanId: UUID,

    val emiNumber: Short,

    val dueDate: LocalDate,

    val principalPart: BigDecimal,

    val interestPart: BigDecimal,

    val totalEmi: BigDecimal,

    val status: String = "PENDING",

    val paidAt: Instant? = null,

    val paymentRef: String? = null,

    val createdAt: Instant = Instant.now()
)

interface LoanEmiRepository :
    CoroutineCrudRepository<LoanEmiEntity, UUID> {

    suspend fun findAllByLoanId(
        loanId: UUID
    ): List<LoanEmiEntity>
}

// =======================================================
// DTOs
// =======================================================

data class LoanStep1Request(
    val fullName: String,
    val dateOfBirth: LocalDate,
    val panNumber: String,
    val fathersName: String?,
    val address: String?,
    val pincode: String?,
    val city: String?,
    val state: String?
)

data class LoanStep2Request(
    val employmentType: String,
    val employerName: String?,
    val monthlyIncome: BigDecimal?,
    val cibilConsent: Boolean
)

data class LoanStep3Request(
    val requestedAmount: BigDecimal,
    val tenureMonths: Short
)

data class LoanStatusResponse(
    val userId: UUID,
    val applicationStatus: String?,
    val approvedAmount: BigDecimal?,
    val interestRate: BigDecimal?,
    val monthlyEmi: BigDecimal?,
    val outstandingBalance: BigDecimal?,
    val accountStatus: String?
)

data class EmiCalculation(
    val principal: BigDecimal,
    val interestRate: BigDecimal,
    val tenureMonths: Short,
    val monthlyEmi: BigDecimal,
    val totalPayable: BigDecimal,
    val totalInterest: BigDecimal
)

// =======================================================
// Exceptions
// =======================================================

sealed class LoanException(
    code: String,
    message: String,
    httpStatus: Int = 400
) : BaseException(code, message) {

    override val httpStatus: Int = httpStatus
}

class LoanNotEligibleException(
    reason: String
) : LoanException(
    "LOAN_NOT_ELIGIBLE",
    reason,
    403
)

class LoanApplicationExistsException : LoanException(
    "LOAN_APPLICATION_EXISTS",
    "Active loan application already exists.",
    409
)

class LoanSessionExpiredException : LoanException(
    "LOAN_SESSION_EXPIRED",
    "Session expired. Please restart loan application.",
    400
)

class LoanAccountNotFoundException(
    userId: UUID
) : LoanException(
    "LOAN_ACCOUNT_NOT_FOUND",
    "Loan account not found for user $userId",
    404
)

class InvalidLoanAmountException(
    amount: BigDecimal
) : LoanException(
    "INVALID_LOAN_AMOUNT",
    "Invalid loan amount ₹$amount",
    400
)

class InvalidLoanTenureException(
    tenure: Short
) : LoanException(
    "INVALID_LOAN_TENURE",
    "Invalid loan tenure $tenure months",
    400
)

// =======================================================
// Loan Service
// =======================================================

@Service
class LoanService(

    private val appRepo: LoanApplicationRepository,

    private val accountRepo: LoanAccountRepository,

    private val emiRepo: LoanEmiRepository,

    private val redisTemplate: ReactiveStringRedisTemplate,

    private val pubSubPublisher: PubSubPublisher        // Production: event-driven flow

) {

    private val log = LoggerFactory.getLogger(javaClass)

    companion object {

        private val SESSION_TTL = Duration.ofMinutes(30)

        private const val SESSION_PREFIX = "loan_session:"

        private val MIN_LOAN_AMOUNT = BigDecimal("1000")

        private val MAX_LOAN_AMOUNT = BigDecimal("1000000")

        private const val MIN_TENURE: Short = 3

        private const val MAX_TENURE: Short = 84
    }

    suspend fun getStatus(
        userId: UUID
    ): LoanStatusResponse {

        val account = accountRepo.findByUserId(userId)

        val app = appRepo.findLatestByUserId(userId)

        return LoanStatusResponse(
            userId = userId,
            applicationStatus = app?.status,
            approvedAmount = app?.approvedAmount ?: account?.principal,
            interestRate = app?.interestRate ?: account?.interestRate,
            monthlyEmi = account?.monthlyEmi,
            outstandingBalance = account?.outstandingBalance,
            accountStatus = account?.status
        )
    }
    //.....................................
    // =======================================================
// EMI Calculator
// =======================================================

fun calculateEmi(
    principal: BigDecimal,
    annualRate: BigDecimal,
    tenureMonths: Short
): EmiCalculation {

    require(principal > BigDecimal.ZERO) {
        "Principal must be greater than zero."
    }

    require(annualRate > BigDecimal.ZERO) {
        "Interest rate must be greater than zero."
    }

    require(tenureMonths > 0) {
        "Tenure must be greater than zero."
    }

    val monthlyRate =
        annualRate.divide(BigDecimal("1200"), 10, RoundingMode.HALF_EVEN)

    val r = monthlyRate.toDouble()
    val n = tenureMonths.toInt()

    val factor = (1 + r).pow(n)

    val emiValue =
        principal.toDouble() * r * factor / (factor - 1)

    val monthlyEmi =
        BigDecimal.valueOf(emiValue)
            .setScale(2, RoundingMode.HALF_UP)

    val totalPayable =
        monthlyEmi.multiply(BigDecimal(n))

    val totalInterest =
        totalPayable.subtract(principal)

    return EmiCalculation(
        principal = principal,
        interestRate = annualRate,
        tenureMonths = tenureMonths,
        monthlyEmi = monthlyEmi,
        totalPayable = totalPayable,
        totalInterest = totalInterest
    )
}

// =======================================================
// STEP 1
// =======================================================

suspend fun submitStep1(
    userId: UUID,
    req: LoanStep1Request
): Result<String, LoanException> {

    val existing = appRepo.findLatestByUserId(userId)

    if (existing != null &&
        existing.status in listOf("SUBMITTED", "UNDER_REVIEW")
    ) {
        return Result.failure(
            LoanApplicationExistsException()
        )
    }

    val sessionKey = "$SESSION_PREFIX$userId"

    redisTemplate
        .opsForHash<String, String>()
        .putAll(
            sessionKey,
            mapOf(
                "fullName" to req.fullName,
                "dateOfBirth" to req.dateOfBirth.toString(),
                "panNumber" to req.panNumber,
                "fathersName" to (req.fathersName ?: ""),
                "address" to (req.address ?: ""),
                "pincode" to (req.pincode ?: ""),
                "city" to (req.city ?: ""),
                "state" to (req.state ?: ""),
                "step" to "1"
            )
        )
        .awaitSingle()

    redisTemplate
        .expire(sessionKey, SESSION_TTL)
        .awaitSingle()

    log.info("Loan Step-1 completed for user {}", userId)

    return Result.success(
        "Step 1 saved. Proceed to step 2."
    )
}

// =======================================================
// STEP 2
// =======================================================

suspend fun submitStep2(
    userId: UUID,
    req: LoanStep2Request
): Result<String, LoanException> {

    if (!req.cibilConsent) {
        return Result.failure(
            LoanNotEligibleException(
                "CIBIL consent required."
            )
        )
    }

    val sessionKey = "$SESSION_PREFIX$userId"

    val currentStep =
        redisTemplate
            .opsForHash<String, String>()
            .get(sessionKey, "step")
            .awaitSingleOrNull()

    if (currentStep != "1") {
        return Result.failure(
            LoanSessionExpiredException()
        )
    }

    redisTemplate
        .opsForHash<String, String>()
        .putAll(
            sessionKey,
            mapOf(
                "employmentType" to req.employmentType,
                "employerName" to (req.employerName ?: ""),
                "monthlyIncome" to
                        (req.monthlyIncome?.toPlainString() ?: "0"),
                "cibilConsent" to "true",
                "step" to "2"
            )
        )
        .awaitSingle()

    redisTemplate
        .expire(sessionKey, SESSION_TTL)
        .awaitSingle()

    log.info("Loan Step-2 completed for user {}", userId)

    return Result.success(
        "Step 2 saved. Proceed to step 3."
    )
}

// =======================================================
// STEP 3
// =======================================================

suspend fun submitStep3(
    userId: UUID,
    req: LoanStep3Request
): Result<LoanStatusResponse, LoanException> {

    // ---------- Validation ----------

    if (req.requestedAmount < MIN_LOAN_AMOUNT ||
        req.requestedAmount > MAX_LOAN_AMOUNT
    ) {
        return Result.failure(
            InvalidLoanAmountException(req.requestedAmount)
        )
    }

    if (req.tenureMonths !in MIN_TENURE..MAX_TENURE) {
        return Result.failure(
            InvalidLoanTenureException(req.tenureMonths)
        )
    }

    val sessionKey = "$SESSION_PREFIX$userId"

    // ---------- Read Redis Session (Non Blocking) ----------

    val entries =
        redisTemplate
            .opsForHash<String, String>()
            .entries(sessionKey)
            .collectList()
            .awaitSingle()

    val session =
        entries.associate { it.key to it.value }

    // ---------- Validate Session ----------

    if (session["step"] != "2") {
        return Result.failure(
            LoanSessionExpiredException()
        )
    }

    // ---------- Save Application ----------

    val application =
        appRepo.save(
            LoanApplicationEntity(
                userId = userId,
                fullName = session["fullName"]!!,
                dateOfBirth = LocalDate.parse(session["dateOfBirth"]!!),
                panNumber = session["panNumber"]!!,
                fathersName = session["fathersName"],
                address = session["address"],
                pincode = session["pincode"],
                city = session["city"],
                state = session["state"],
                employmentType = session["employmentType"],
                employerName = session["employerName"],
                monthlyIncome = session["monthlyIncome"]?.let(::BigDecimal),
                cibilConsent = true,
                requestedAmount = req.requestedAmount,
                tenureMonths = req.tenureMonths,
                status = "SUBMITTED"
            )
        )

    // ---------- Delete Redis Session ----------

    redisTemplate
        .delete(sessionKey)
        .awaitSingleOrNull()

    log.info(
        "Loan application submitted userId={} applicationId={} amount={}",
        userId,
        application.id,
        req.requestedAmount
    )

    // ---------- Publish Event ----------

    try {

        pubSubPublisher.publish(

            "loan-application-submitted",

            mapOf(
                "applicationId" to application.id.toString(),
                "userId" to userId.toString(),
                "amount" to req.requestedAmount.toPlainString(),
                "tenureMonths" to req.tenureMonths.toString()
            )

        )

        log.info(
            "loan-application-submitted event published {}",
            application.id
        )

    } catch (ex: Exception) {

        log.error(
            "Unable to publish loan event {}",
            ex.message,
            ex
        )
    }

    return Result.success(
        getStatus(userId)
    )
}

// =======================================================
// EMI Schedule
// =======================================================

suspend fun getEmiSchedule(
    userId: UUID
): List<LoanEmiEntity> {

    val account =
        accountRepo.findByUserId(userId)
            ?: throw LoanAccountNotFoundException(userId)

    return emiRepo.findAllByLoanId(account.id!!)
}
}