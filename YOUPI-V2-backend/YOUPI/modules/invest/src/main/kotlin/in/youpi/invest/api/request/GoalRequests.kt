package `in`.youpi.invest.api.request

import jakarta.validation.constraints.FutureOrPresent
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Positive
import jakarta.validation.constraints.PositiveOrZero
import java.math.BigDecimal
import java.time.LocalDate

data class CreateGoalRequest(
    @field:NotBlank(message = "title is required")
    val title: String,
    val category: String? = null,
    val categoryEmoji: String? = null,
    @field:Positive(message = "targetAmount must be positive")
    val targetAmount: BigDecimal,
    @field:FutureOrPresent(message = "deadline must be today or in the future")
    val deadline: LocalDate,
    // DAILY / WEEKLY / MONTHLY -- validated against SavingFrequency enum
    // in GoalService rather than here, so an invalid value gets the same
    // ValidationException shape as the rest of this module.
    @field:NotBlank(message = "frequency is required")
    val frequency: String,
    @field:Positive(message = "installmentAmount must be positive")
    val installmentAmount: BigDecimal
)

// Patch semantics: only non-null fields are applied. Matches the
// frontend's existing "pause/resume auto-debit, edit target" scope
// (Spec Sec 4.2) -- deliberately does not allow changing frequency
// mid-goal, since that would orphan next_deduction_date's cadence.
data class UpdateGoalRequest(
    val targetAmount: BigDecimal? = null,
    val installmentAmount: BigDecimal? = null,
    val deadline: LocalDate? = null,
    val autoDebitActive: Boolean? = null
)

data class TopupGoalRequest(
    @field:Positive(message = "amount must be positive")
    val amount: BigDecimal,
    @field:NotBlank(message = "idempotencyKey is required")
    val idempotencyKey: String
)