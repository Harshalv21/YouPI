package `in`.youpi.invest.augmont

import com.fasterxml.jackson.annotation.JsonIgnoreProperties
import com.fasterxml.jackson.annotation.JsonProperty
import java.math.BigDecimal

// ═══════════════════════════════════════════════════════════
// Augmont Merchant API — Domain Models
// ═══════════════════════════════════════════════════════════

// ── Auth ──

data class AugmontLoginRequest(
    val email: String,
    val password: String
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontLoginResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontAuthResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontAuthResult(
    @JsonProperty("access_token") val accessToken: String,
    @JsonProperty("token_type") val tokenType: String?,
    @JsonProperty("merchant") val merchant: AugmontMerchantInfo?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontMerchantInfo(
    val id: String?,
    val name: String?,
    val email: String?
)

// ── Rates ──

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontRatesResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontRatesResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontRatesResult(
    val data: AugmontRatesData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontRatesData(
    val blockId: String?,
    val goldBuy: BigDecimal?,
    val goldSell: BigDecimal?,
    val silverBuy: BigDecimal?,
    val silverSell: BigDecimal?,
    @JsonProperty("gold_24k") val gold24k: BigDecimal?,
    @JsonProperty("gold_22k") val gold22k: BigDecimal?,
    val gst: BigDecimal?,
    val goldBuyGst: BigDecimal?,
    val silverBuyGst: BigDecimal?,
    val validUpTo: String?,
    val validitySeconds: Int?
)

// ── Buy ──

data class AugmontBuyRequest(
    val lockPrice: BigDecimal,
    val metalType: String = "gold",      // "gold" or "silver"
    val quantity: BigDecimal? = null,     // qty in grams (either qty or amount)
    val amount: BigDecimal? = null,       // amount in INR (either qty or amount)
    val blockId: String,
    val uniqueId: String,                 // Augmont user uniqueId
    val merchantTransactionId: String,
    val userName: String? = null,
    val userEmail: String? = null,
    val userMobile: String? = null,
    val modeOfPayment: String = "NEFT"
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBuyResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontBuyResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBuyResult(
    val data: AugmontBuyData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBuyData(
    @JsonProperty("merchantTransactionId") val merchantTransactionId: String?,
    @JsonProperty("transactionId") val transactionId: String?,
    val quantity: BigDecimal?,
    val totalAmount: BigDecimal?,
    val pricePerGram: BigDecimal?,
    val metalType: String?,
    val userName: String?,
    val transactionStatus: String?,
    val goldBalance: BigDecimal?,
    val silverBalance: BigDecimal?
)

// ── Buy Info ──

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBuyInfoResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontBuyInfoResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBuyInfoResult(
    val data: AugmontBuyInfoData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBuyInfoData(
    val transactionId: String?,
    val merchantTransactionId: String?,
    val quantity: BigDecimal?,
    val totalAmount: BigDecimal?,
    val pricePerGram: BigDecimal?,
    val metalType: String?,
    val transactionStatus: String?,
    val createdAt: String?
)

// ── Sell ──

data class AugmontSellRequest(
    val lockPrice: BigDecimal,
    val metalType: String = "gold",      // "gold" or "silver"
    val quantity: BigDecimal,            // grams to sell
    val blockId: String,
    val uniqueId: String,
    val merchantTransactionId: String,
    val userName: String? = null,
    val modeOfPayment: String = "NEFT",
    val bankAccountId: String? = null    // Augmont bank account ID
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontSellResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontSellResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontSellResult(
    val data: AugmontSellData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontSellData(
    val merchantTransactionId: String?,
    val transactionId: String?,
    val quantity: BigDecimal?,
    val totalAmount: BigDecimal?,
    val pricePerGram: BigDecimal?,
    val metalType: String?,
    val transactionStatus: String?,
    val goldBalance: BigDecimal?,
    val silverBalance: BigDecimal?
)

// ── User ──

data class AugmontCreateUserRequest(
    val userName: String,
    val userEmail: String,
    val userMobile: String,
    val dateOfBirth: String? = null,
    val nomineeName: String? = null,
    val nomineeRelation: String? = null,
    val nomineeDate: String? = null,
    val userPincode: String? = null,
    val userAddress: String? = null,
    val userCity: String? = null,
    val userState: String? = null,
    val panNumber: String? = null,
    val utmSource: String? = null,
    val utmMedium: String? = null,
    val utmCampaign: String? = null
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontUserResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontUserResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontUserResult(
    val data: AugmontUserData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontUserData(
    val uniqueId: String?,
    val userName: String?,
    val userEmail: String?,
    val userMobile: String?,
    val dateOfBirth: String?,
    val kycStatus: String?,
    val createdAt: String?
)

// ── Passbook ──

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontPassbookResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontPassbookResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontPassbookResult(
    val data: AugmontPassbookData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontPassbookData(
    val goldGrms: BigDecimal?,
    val silverGrms: BigDecimal?,
    val goldBalance: BigDecimal?,
    val silverBalance: BigDecimal?,
    val totalGoldBuy: BigDecimal?,
    val totalSilverBuy: BigDecimal?
)

// ── FD Schemes ──

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdSchemesResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontFdSchemesResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdSchemesResult(
    val data: List<AugmontFdScheme>?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdScheme(
    val id: String?,
    val name: String?,
    val minTenure: Int?,
    val maxTenure: Int?,
    val minWeight: BigDecimal?,
    val maxWeight: BigDecimal?,
    val interestRate: BigDecimal?,
    val description: String?,
    val status: String?
)

// ── FD Pre-Order (Interest Preview) ──

data class AugmontFdPreOrderRequest(
    val goldWeight: BigDecimal,
    val tenure: Int,
    val schemeId: String
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdPreOrderResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontFdPreOrderResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdPreOrderResult(
    val data: AugmontFdPreOrderData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdPreOrderData(
    val goldWeight: BigDecimal?,
    val tenure: Int?,
    val interestRate: BigDecimal?,
    val maturityWeight: BigDecimal?,
    val interestWeight: BigDecimal?,
    val schemeId: String?
)

// ── FD Create ──

data class AugmontFdCreateRequest(
    val goldWeight: BigDecimal,
    val tenure: Int,
    val schemeId: String,
    val uniqueId: String,
    val merchantTransactionId: String
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdCreateResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontFdCreateResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdCreateResult(
    val data: AugmontFdOrder?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdOrder(
    val id: String?,
    val goldWeight: BigDecimal?,
    val tenure: Int?,
    val interestRate: BigDecimal?,
    val maturityWeight: BigDecimal?,
    val interestWeight: BigDecimal?,
    val maturityDate: String?,
    val status: String?,
    val createdAt: String?
)

// ── FD Pre-Close ──

data class AugmontFdPreCloseRequest(
    val fdOrderId: String,
    val uniqueId: String
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdPreCloseResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontFdPreCloseResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdPreCloseResult(
    val data: AugmontFdPreCloseData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontFdPreCloseData(
    val fdOrderId: String?,
    val goldReturned: BigDecimal?,
    val penaltyWeight: BigDecimal?,
    val interestEarned: BigDecimal?,
    val status: String?
)

// ── Historical / Rolling Data ──

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontRollingDataResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontRollingDataResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontRollingDataResult(
    val data: List<AugmontPricePoint>?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontPricePoint(
    val date: String?,
    val goldPrice: BigDecimal?,
    val silverPrice: BigDecimal?
)

// ── Products (Physical) ──

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontProductsResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontProductsResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontProductsResult(
    val data: List<AugmontProduct>?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontProduct(
    val sku: String?,
    val name: String?,
    val metalType: String?,
    val weight: BigDecimal?,
    val price: BigDecimal?,
    val imageUrl: String?,
    val description: String?,
    val inStock: Boolean?
)

// ── User Bank (for Sell payouts) ──

data class AugmontAddBankRequest(
    val accountNumber: String,
    val ifscCode: String,
    val accountName: String,
    val uniqueId: String
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBankResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontBankResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBankResult(
    val data: AugmontBankData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontBankData(
    val id: String?,
    val accountNumber: String?,
    val ifscCode: String?,
    val accountName: String?,
    val status: String?
)

// ── KYC ──

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontKycResponse(
    val statusCode: Int?,
    val message: String?,
    val result: AugmontKycResult?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontKycResult(
    val data: AugmontKycData?
)

@JsonIgnoreProperties(ignoreUnknown = true)
data class AugmontKycData(
    val kycStatus: String?,
    val panNumber: String?,
    val panStatus: String?,
    val aadharStatus: String?
)
