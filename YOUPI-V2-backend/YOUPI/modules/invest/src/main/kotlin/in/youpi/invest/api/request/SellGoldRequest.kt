package `in`.youpi.invest.api.request

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Positive
import java.math.BigDecimal

data class SellGoldRequest(
    @field:Positive(message = "grams must be positive")
    val grams: BigDecimal,
    @field:NotBlank(message = "idempotencyKey is required")
    val idempotencyKey: String,
    val metalType: String = "gold",
    val bankAccountId: String?
)