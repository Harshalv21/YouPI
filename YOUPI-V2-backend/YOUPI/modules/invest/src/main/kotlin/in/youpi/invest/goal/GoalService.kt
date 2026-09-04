package `in`.youpi.invest.goal

import `in`.youpi.core.BaseException
import `in`.youpi.core.NotFoundException
import `in`.youpi.core.Result
import `in`.youpi.core.ValidationException
import `in`.youpi.core.WalletCreditPort
import `in`.youpi.core.WalletDebitOutcome
import `in`.youpi.core.WalletDebitPort
import `in`.youpi.core.WalletDebitRejectionReason
import `in`.youpi.invest.service.GoldException
import `in`.youpi.invest.service.InvestService
import org.slf4j.LoggerFactory
import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import kotlinx.coroutines.reactive.awaitSingle
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

// ── Frequency ──

enum class SavingFrequency { DAILY, WEEKLY, MONTHLY }

fun parseFrequency(raw: String): SavingFrequency =
    runCatching { SavingFrequency.valueOf(raw.uppercase()) }
        .getOrElse { throw ValidationException("frequency", "frequency must be one of DAILY, WEEKLY, MONTHLY") }

private fun advance(date: LocalDate, frequency: SavingFrequency): LocalDate = when (frequency) {
    SavingFrequency.DAILY -> date.plusDays(1)
    SavingFrequency.WEEKLY -> date.plusWeeks(1)
    SavingFrequency.MONTHLY -> date.plusMonths(1)
}

// ── Entities ──

@Table("gold_goals")
data class GoalEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val title: String,
    val category: String? = null,
    val categoryEmoji: String? = null,
    val targetAmount: BigDecimal,
    val savedAmount: BigDecimal = BigDecimal.ZERO,
    val frequency: String,
    val installmentAmount: BigDecimal,
    val nextDeductionDate: LocalDate,
    val autoDebitActive: Boolean = true,
    val missedDebitAttempts: Short = 0,
    val completed: Boolean = false,
    val createdAt: Instant = Instant.now(),
    val deadline: LocalDate
)

interface GoalRepository : CoroutineCrudRepository<GoalEntity, UUID> {
    suspend fun findAllByUserId(userId: UUID): List<GoalEntity>

    @Query("""
        SELECT * FROM gold_goals
        WHERE auto_debit_active = true AND completed = false
          AND next_deduction_date <= :today
    """)
    suspend fun findDueGoals(today: LocalDate): List<GoalEntity>
}

@Table("gold_goal_contributions")
data class GoalContributionEntity(
    @Id val id: UUID? = null,
    val goalId: UUID,
    val goldTxnId: UUID? = null,
    val type: String, // AUTO_DEBIT / MANUAL_TOPUP
    val grams: BigDecimal,
    val pricePerGram: BigDecimal,
    val createdAt: Instant = Instant.now()
)

interface GoalContributionRepository : CoroutineCrudRepository<GoalContributionEntity, UUID> {
    @Query("SELECT * FROM gold_goal_contributions WHERE goal_id = :goalId ORDER BY created_at DESC")
    suspend fun findAllByGoalId(goalId: UUID): List<GoalContributionEntity>
}

// ── Response DTOs ──
// Field names mirror GoalModel/GoalContribution in the Flutter app
// (lib/data/models/goal_model.dart) so the repository layer on the
// frontend can deserialize with minimal remapping.

data class GoalContributionResponse(
    val type: String,
    val date: Instant,
    val grams: BigDecimal,
    val pricePerGram: BigDecimal
)

data class GoalResponse(
    val id: UUID,
    val title: String,
    val category: String?,
    val categoryEmoji: String?,
    val targetAmount: BigDecimal,
    val savedAmount: BigDecimal,
    val createdAt: Instant,
    val deadline: LocalDate,
    val frequency: String,
    val installmentAmount: BigDecimal,
    val nextDeductionDate: LocalDate,
    val autoDebitActive: Boolean,
    val completed: Boolean,
    val contributions: List<GoalContributionResponse> = emptyList()
)

// ── Exceptions ──


/**
 * Goal-based recurring gold investing ("Gold SIP"). See the Gold SIP
 * Feature Spec handoff doc for the original design; this implements
 * Sections 4.1-4.3 of it.
 *
 * Every SIP/manual contribution is just a normal InvestService.buyGold()
 * call, tagged to a goal via gold_goal_contributions.gold_txn_id -- there
 * is no separate ledger, per the spec's stated design.
 */
@Service
class GoalService(
    private val goalRepo: GoalRepository,
    private val contributionRepo: GoalContributionRepository,
    private val investService: InvestService,
    private val walletDebitPort: WalletDebitPort,
    private val walletCreditPort: WalletCreditPort,
    private val redisTemplate: ReactiveStringRedisTemplate
) {
    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        // Consecutive insufficient-balance misses before auto-debit is
        // paused and the user has to resume it manually. Open decision
        // 6.1 in the spec -- "retry N times" -- resolved as: retry daily,
        // don't push the due date forward, for up to this many attempts.
        private const val MAX_MISSED_ATTEMPTS: Short = 3
        private const val SCHEDULER_LOCK_KEY = "lock:gold-sip-scheduler"
    }

    // ══════════════════════════════════════
    // CRUD
    // ══════════════════════════════════════

    suspend fun createGoal(
        userId: UUID,
        title: String,
        category: String?,
        categoryEmoji: String?,
        targetAmount: BigDecimal,
        deadline: LocalDate,
        frequency: String,
        installmentAmount: BigDecimal
    ): GoalResponse {
        val freq = parseFrequency(frequency)
        if (installmentAmount > targetAmount) {
            throw ValidationException("installmentAmount", "installmentAmount cannot exceed targetAmount")        }

        val saved = goalRepo.save(
            GoalEntity(
                userId = userId,
                title = title,
                category = category,
                categoryEmoji = categoryEmoji,
                targetAmount = targetAmount,
                frequency = freq.name,
                installmentAmount = installmentAmount,
                nextDeductionDate = advance(LocalDate.now(), freq),
                deadline = deadline
            )
        )
        return saved.toResponse(emptyList())
    }

    suspend fun listGoals(userId: UUID): List<GoalResponse> =
        goalRepo.findAllByUserId(userId).map { it.toResponse(emptyList()) }

    suspend fun getGoal(userId: UUID, goalId: UUID): GoalResponse {
        val goal = ownedGoal(userId, goalId)
        val contributions = contributionRepo.findAllByGoalId(goalId)
        return goal.toResponse(contributions.map { it.toResponse() })
    }

    suspend fun updateGoal(
        userId: UUID,
        goalId: UUID,
        targetAmount: BigDecimal?,
        installmentAmount: BigDecimal?,
        deadline: LocalDate?,
        autoDebitActive: Boolean?
    ): GoalResponse {
        val goal = ownedGoal(userId, goalId)

        val newTarget = targetAmount ?: goal.targetAmount
        val newInstallment = installmentAmount ?: goal.installmentAmount
        if (newInstallment > newTarget) {
            throw ValidationException("installmentAmount", "installmentAmount cannot exceed targetAmount")        }

        val resumed = autoDebitActive == true && !goal.autoDebitActive
        val updated = goalRepo.save(
            goal.copy(
                targetAmount = newTarget,
                installmentAmount = newInstallment,
                deadline = deadline ?: goal.deadline,
                autoDebitActive = autoDebitActive ?: goal.autoDebitActive,
                // Resuming after a pause (e.g. the 3-miss auto-pause) starts
                // the retry count fresh, and gives the next attempt a full
                // cycle rather than trying again immediately.
                missedDebitAttempts = if (resumed) 0 else goal.missedDebitAttempts,
                nextDeductionDate = if (resumed) advance(LocalDate.now(), parseFrequency(goal.frequency)) else goal.nextDeductionDate
            )
        )
        val contributions = contributionRepo.findAllByGoalId(goalId)
        return updated.toResponse(contributions.map { it.toResponse() })
    }

    suspend fun deleteGoal(userId: UUID, goalId: UUID) {
        ownedGoal(userId, goalId)
        goalRepo.deleteById(goalId)
    }

    // ══════════════════════════════════════
    // Manual top-up (same buyGold() path, tagged to goal)
    // ══════════════════════════════════════

    suspend fun topup(userId: UUID, goalId: UUID, amount: BigDecimal, idempotencyKey: String): GoalResponse {
        val goal = ownedGoal(userId, goalId)
        if (goal.completed) throw ValidationException("goalId", "This goal is already completed")

        val buyResult = investService.buyGold(
            userId = userId,
            amountInr = amount,
            idempotencyKey = "goal_topup_$idempotencyKey",
            // gold_transactions.triggered_by has a DB CHECK constraint
            // (chk_gold_triggered) allowing only MANUAL/RECHARGE_AUTO/SIP --
            // "MANUAL" is the closest fit for an on-demand goal top-up.
            triggeredBy = "MANUAL"
        )
        val buyResponse = when (buyResult) {
            is Result.Success -> buyResult.value
            is Result.Failure -> throw buyResult.error
        }

        val pricePerGram = if (buyResponse.grams > BigDecimal.ZERO)
            buyResponse.amountInr.divide(buyResponse.grams, 2, RoundingMode.HALF_EVEN)
        else BigDecimal.ZERO

        contributionRepo.save(
            GoalContributionEntity(
                goalId = goalId,
                goldTxnId = buyResponse.txnId,
                type = "MANUAL_TOPUP",
                grams = buyResponse.grams,
                pricePerGram = pricePerGram
            )
        )

        val newSaved = goal.savedAmount.add(buyResponse.amountInr)
        val completed = newSaved >= goal.targetAmount
        val updated = goalRepo.save(
            goal.copy(
                savedAmount = newSaved,
                completed = completed,
                autoDebitActive = if (completed) false else goal.autoDebitActive
            )
        )
        val contributions = contributionRepo.findAllByGoalId(goalId)
        return updated.toResponse(contributions.map { it.toResponse() })
    }

    private suspend fun ownedGoal(userId: UUID, goalId: UUID): GoalEntity {
        val goal = goalRepo.findById(goalId) ?: throw NotFoundException("Goal", goalId.toString())
        // 404, not 403 -- same reasoning as InvestService.getBuyInvoice():
        // don't leak that a goal id exists for a different user.
        if (goal.userId != userId) throw NotFoundException("Goal", goalId.toString())
        return goal
    }

    private fun GoalEntity.toResponse(contributions: List<GoalContributionResponse>) = GoalResponse(
        id = id!!, title = title, category = category, categoryEmoji = categoryEmoji,
        targetAmount = targetAmount, savedAmount = savedAmount, createdAt = createdAt,
        deadline = deadline, frequency = frequency, installmentAmount = installmentAmount,
        nextDeductionDate = nextDeductionDate, autoDebitActive = autoDebitActive,
        completed = completed, contributions = contributions
    )

    private fun GoalContributionEntity.toResponse() =
        GoalContributionResponse(type = type, date = createdAt, grams = grams, pricePerGram = pricePerGram)

    // ══════════════════════════════════════
    // Auto-debit engine — the actual new piece (Spec Sec 4.3)
    // ══════════════════════════════════════

    /**
     * Runs once a day. Cloud Run can have more than one warm instance, so
     * a bare @Scheduled here could double-fire (spec's open decision 6.3)
     * -- guarded with a short-lived Redis lock (SET NX), same Redis
     * instance InvestService already uses for the rates cache.
     *
     * Note: kept as a single in-process cron for now, consistent with
     * WalletService.sweepPendingTopups() elsewhere in this codebase,
     * which uses the same fixedDelay approach without a lock. If Cloud
     * Run min-instances ever goes above 1, revisit -- a Cloud Scheduler
     * + authenticated-endpoint pattern would be a more robust fix than
     * the Redis lock alone.
     */
    // TEMP for testing (Sep 4) -- fires every minute; the existing
    // 30-min Redis lock prevents duplicate processing across repeated
    // fires, so this is safe. Revert to "0 30 3 * * *" (09:00 IST)
    // after confirming the scheduler works end-to-end.
    @Scheduled(cron = "0 30 3 * * *") // 03:30 UTC = 09:00 IST
    suspend fun runDueGoalDebits() {
        val gotLock = redisTemplate.opsForValue()
            .setIfAbsent(SCHEDULER_LOCK_KEY, Instant.now().toString(), Duration.ofMinutes(30))
            .awaitSingle()
        if (gotLock != true) {
            log.info("Gold SIP scheduler: lock held by another instance, skipping this run")
            return
        }

        val due = try {
            goalRepo.findDueGoals(LocalDate.now())
        } catch (e: Exception) {
            log.error("Gold SIP scheduler: failed to fetch due goals", e)
            return
        }

        if (due.isEmpty()) return
        log.info("Gold SIP scheduler: {} goal(s) due", due.size)

        for (goal in due) {
            try {
                processDueGoal(goal)
            } catch (e: Exception) {
                // One goal's failure must never block the rest of the batch.
                log.error("Gold SIP scheduler: unexpected error processing goalId={}, userId={}", goal.id, goal.userId, e)
            }
        }
    }

    private suspend fun processDueGoal(goal: GoalEntity) {
        val remaining = goal.targetAmount.subtract(goal.savedAmount)
        if (remaining <= BigDecimal.ZERO) {
            goalRepo.save(goal.copy(completed = true, autoDebitActive = false))
            return
        }
        val debitAmount = goal.installmentAmount.min(remaining)
        val cycleKey = "goalsip_${goal.id}_${goal.nextDeductionDate}"

        val debitOutcome = walletDebitPort.debitForService(
            userId = goal.userId,
            walletType = "NBFC",
            amount = debitAmount,
            serviceCode = "GOLD_SIP",
            referenceId = goal.id,
            description = "Gold SIP: ${goal.title} (₹$debitAmount)",
            idempotencyKey = "${cycleKey}_wallet"
        )

        when (debitOutcome) {
            is WalletDebitOutcome.Rejected -> {
                if (debitOutcome.reason == WalletDebitRejectionReason.INSUFFICIENT_BALANCE) {
                    val attempts = (goal.missedDebitAttempts + 1).toShort()
                    val pause = attempts >= MAX_MISSED_ATTEMPTS
                    log.warn(
                        "Gold SIP: debit skipped (insufficient balance), goalId={}, userId={}, attempt={}/{}{}",
                        goal.id, goal.userId, attempts, MAX_MISSED_ATTEMPTS, if (pause) " -- pausing auto-debit" else ""
                    )
                    // Deliberately leave nextDeductionDate unchanged so the
                    // same cycle is retried tomorrow (unless now paused).
                    goalRepo.save(goal.copy(missedDebitAttempts = attempts, autoDebitActive = !pause))
                } else {
                    log.error(
                        "Gold SIP: debit rejected for a non-balance reason, goalId={}, userId={}, reason={}, message={}",
                        goal.id, goal.userId, debitOutcome.reason, debitOutcome.message
                    )
                }
            }
            is WalletDebitOutcome.Success -> {
                val buyResult = investService.buyGold(
                    userId = goal.userId,
                    amountInr = debitAmount,
                    idempotencyKey = "${cycleKey}_buy",
                    // Must match the DB CHECK constraint's allowed value --
                    // "SIP", not "GOLD_SIP".
                    triggeredBy = "SIP"
                )
                when (buyResult) {
                    is Result.Success -> onDebitAndBuySucceeded(goal, debitAmount, buyResult.value.txnId, buyResult.value.grams, buyResult.value.amountInr)
                    is Result.Failure -> reverseAndLogFailure(goal, debitAmount, cycleKey, buyResult.error)
                }
            }
        }
    }

    private suspend fun onDebitAndBuySucceeded(
        goal: GoalEntity, debitAmount: BigDecimal, txnId: UUID, grams: BigDecimal, actualAmount: BigDecimal
    ) {
        val pricePerGram = if (grams > BigDecimal.ZERO) actualAmount.divide(grams, 2, RoundingMode.HALF_EVEN) else BigDecimal.ZERO
        contributionRepo.save(
            GoalContributionEntity(goalId = goal.id!!, goldTxnId = txnId, type = "AUTO_DEBIT", grams = grams, pricePerGram = pricePerGram)
        )

        val newSaved = goal.savedAmount.add(actualAmount)
        val completed = newSaved >= goal.targetAmount
        goalRepo.save(
            goal.copy(
                savedAmount = newSaved,
                missedDebitAttempts = 0,
                nextDeductionDate = advance(goal.nextDeductionDate, parseFrequency(goal.frequency)),
                completed = completed,
                autoDebitActive = if (completed) false else goal.autoDebitActive
            )
        )
        log.info("Gold SIP: auto-debited ₹{} for goalId={}, userId={} [txnId={}]", debitAmount, goal.id, goal.userId, txnId)
    }

    private suspend fun reverseAndLogFailure(goal: GoalEntity, debitAmount: BigDecimal, cycleKey: String, error: GoldException) {
        log.error(
            "Gold SIP: buyGold failed after wallet debit -- reversing. goalId={}, userId={}, amount=₹{}, error={}",
            goal.id, goal.userId, debitAmount, error.message
        )
        val reversed = walletCreditPort.reverseDebit(
            userId = goal.userId,
            walletType = "NBFC",
            amountPaise = debitAmount.multiply(BigDecimal(100)).toLong(),
            referenceType = "GOLD_SIP",
            referenceId = goal.id,
            description = "Reversal: Gold SIP buy failed for ${goal.title}",
            idempotencyKey = "${cycleKey}_reversal"
        )
        if (!reversed) {
            log.error(
                "CRITICAL: Gold SIP wallet reversal FAILED, goalId={}, userId={}, amount=₹{} -- needs manual wallet credit.",
                goal.id, goal.userId, debitAmount
            )
        }
        // Left as-is (nextDeductionDate unchanged, missedDebitAttempts
        // untouched) so this cycle is simply retried tomorrow -- this
        // path is "gold buy failed", not "insufficient balance", so it
        // doesn't count against MAX_MISSED_ATTEMPTS.
    }
}