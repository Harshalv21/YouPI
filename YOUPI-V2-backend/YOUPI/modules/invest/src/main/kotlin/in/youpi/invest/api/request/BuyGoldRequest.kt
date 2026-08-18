package `in`.youpi.invest.api.request

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Positive
import java.math.BigDecimal

data class BuyGoldRequest(
    @field:Positive(message = "amount must be positive")
    val amount: BigDecimal,
    @field:NotBlank(message = "idempotencyKey is required")
    val idempotencyKey: String,
    val metalType: String = "gold"
)