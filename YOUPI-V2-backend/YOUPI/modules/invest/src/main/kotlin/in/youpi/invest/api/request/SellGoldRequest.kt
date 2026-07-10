package `in`.youpi.invest.api.request

import java.math.BigDecimal

data class SellGoldRequest(
    val grams: BigDecimal,
    val idempotencyKey: String,
    val metalType: String = "gold",
    val bankAccountId: String?
)