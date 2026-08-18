package `in`.youpi.onboarding.service

import `in`.youpi.core.BaseException
import org.slf4j.LoggerFactory
import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Modifying
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.stereotype.Service
import java.time.Instant
import java.util.UUID

// ── Entity ── -- id is DB-generated (gen_random_uuid() in V19 migration),
// same pattern as WalletEntity: nullable id, no Persistable needed since
// we never assign the id client-side.

@Table("onboarding_answers")
data class OnboardingAnswerEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val questionId: String,
    val optionIds: String,      // comma-joined option ids
    val otherText: String? = null,
    val answeredAt: Instant = Instant.now()
)

interface OnboardingAnswerRepository : CoroutineCrudRepository<OnboardingAnswerEntity, UUID> {

    suspend fun findAllByUserId(userId: UUID): List<OnboardingAnswerEntity>

    // @Modifying REQUIRED on R2DBC mutating queries (established pattern,
    // see GCP migration notes -- omitting it silently no-ops the delete).
    @Modifying
    @Query("DELETE FROM onboarding_answers WHERE user_id = :userId AND question_id = :questionId")
    suspend fun deleteByUserIdAndQuestionId(userId: UUID, questionId: String): Int
}

// ── DTOs ──

data class OnboardingAnswerItem(
    val questionId: String,
    val optionIds: List<String>,
    val otherText: String? = null
)

data class SubmitOnboardingRequest(
    val answers: List<OnboardingAnswerItem>
)

data class OnboardingAnswerResponse(
    val questionId: String,
    val optionIds: List<String>,
    val otherText: String?,
    val answeredAt: Instant
)

data class OnboardingAnswersResponse(
    val userId: UUID,
    val answers: List<OnboardingAnswerResponse>
)

// ── Exceptions ──

sealed class OnboardingException(code: String, message: String, httpStatus: Int = 400)
    : BaseException(code, message) { override val httpStatus: Int = httpStatus }

class OnboardingNoValidAnswersException : OnboardingException(
    "ONBOARDING_NO_VALID_ANSWERS", "No valid answers were submitted", 422
)

@Service
class OnboardingService(
    private val repo: OnboardingAnswerRepository
) {
    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        // Server-side whitelist -- never trust client-sent questionIds blindly,
        // same reasoning as resolveAuthoritativePlan() in RechargeService.
        private val VALID_QUESTIONS = setOf(
            "monthly_bills", "bill_amount", "income_pattern",
            "saving_goal", "savings_location"
        )
        private const val MAX_OTHER_LEN = 200
        private const val MAX_OPTIONS_PER_QUESTION = 8
    }

    suspend fun submit(userId: UUID, req: SubmitOnboardingRequest) {
        var savedCount = 0

        for (item in req.answers) {
            if (item.questionId !in VALID_QUESTIONS) {
                log.warn("Onboarding: dropping unknown questionId={} for user={}", item.questionId, userId)
                continue
            }
            if (item.optionIds.isEmpty() || item.optionIds.size > MAX_OPTIONS_PER_QUESTION) continue

            val other = item.otherText
                ?.trim()
                ?.take(MAX_OTHER_LEN)
                ?.ifBlank { null }

            // Upsert via delete+insert (simplest with R2DBC/CoroutineCrudRepository;
            // UNIQUE(user_id, question_id) in V19 makes this safe for re-onboarding).
            repo.deleteByUserIdAndQuestionId(userId, item.questionId)
            repo.save(
                OnboardingAnswerEntity(
                    userId = userId,
                    questionId = item.questionId,
                    optionIds = item.optionIds.joinToString(","),
                    otherText = other
                )
            )
            savedCount++
        }

        if (savedCount == 0) throw OnboardingNoValidAnswersException()
        log.info("Onboarding: saved {} answer(s) for user={}", savedCount, userId)
    }

    suspend fun get(userId: UUID): OnboardingAnswersResponse {
        val rows = repo.findAllByUserId(userId)
        return OnboardingAnswersResponse(
            userId = userId,
            answers = rows.map {
                OnboardingAnswerResponse(
                    questionId = it.questionId,
                    optionIds = it.optionIds.split(",").filter { s -> s.isNotBlank() },
                    otherText = it.otherText,
                    answeredAt = it.answeredAt
                )
            }
        )
    }
}