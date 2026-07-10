package `in`.youpi.invest.api.request

import java.math.BigDecimal

data class BuyGoldRequest(
    val amount: BigDecimal,
    val idempotencyKey: String,
    val metalType: String = "gold"
)