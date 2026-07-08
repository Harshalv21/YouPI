package `in`.youpi.invest.augmont

import com.fasterxml.jackson.databind.ObjectMapper
import `in`.youpi.core.ExternalServiceException
import kotlinx.coroutines.reactive.awaitFirstOrNull
import kotlinx.coroutines.reactive.awaitSingle
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.data.redis.core.ReactiveStringRedisTemplate
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.client.MultipartBodyBuilder
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.BodyInserters
import org.springframework.web.reactive.function.client.WebClient
import org.springframework.web.reactive.function.client.awaitBody
import java.math.BigDecimal
import java.time.Duration
import java.util.UUID

/**
 * Central Augmont Merchant API HTTP client.
 *
 * Handles:
 * - Auto-login via POST /merchant/v1/auth/login
 * - Token caching in Redis (23h TTL — Augmont tokens expire at 24h)
 * - Automatic re-authentication on 401 errors
 * - multipart/form-data encoding (Augmont requirement)
 * - Rate-limit awareness (Augmont limits rates endpoint to 10 calls/min)
 *
 *
 * NOTE: Previously this used inline functions with reified type parameters,
 * which caused issues with the kotlin-spring compiler plugin (since it marks
 * @Component classes as `open` and virtual members can't be inline).
 * Now, we explicitly pass the `Class<T>` to generic `doGet/doPost/doPut` helpers.
 */
@Component
class AugmontClient(
    @Value("\${youpi.augmont.base-url:https://uat-api.augmont.com}") private val baseUrl: String,
    @Value("\${youpi.augmont.email:}") private val email: String,
    @Value("\${youpi.augmont.password:}") private val password: String,
    private val redisTemplate: ReactiveStringRedisTemplate,
    private val objectMapper: ObjectMapper
) {

    private val log = LoggerFactory.getLogger(javaClass)

    private val webClient: WebClient = WebClient.builder()
        .baseUrl(baseUrl)
        .defaultHeader(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)
        .codecs { it.defaultCodecs().maxInMemorySize(2 * 1024 * 1024) }
        .build()

    companion object {
        private const val REDIS_TOKEN_KEY = "augmont:merchant:token"
        private val TOKEN_TTL = Duration.ofHours(23)
    }

    // ── Auth ──

    /**
     * Retrieves a valid access token. Returns a cached token from Redis if available,
     * otherwise performs a fresh login and caches the result.
     */
    suspend fun getAccessToken(): String {
        val cached = redisTemplate.opsForValue().get(REDIS_TOKEN_KEY).awaitFirstOrNull()
        if (!cached.isNullOrBlank()) return cached
        return login()
    }

    /**
     * Performs merchant login and caches the token in Redis for 23 hours.
     */
    private suspend fun login(): String {
        log.info("Augmont: Performing merchant login (email={})", email)

        val body = MultipartBodyBuilder().apply {
            part("email", email)
            part("password", password)
        }.build()

        val response = webClient.post()
            .uri("/merchant/v1/auth/login")
            .contentType(MediaType.MULTIPART_FORM_DATA)
            .body(BodyInserters.fromMultipartData(body))
            .retrieve()
            .awaitBody<AugmontLoginResponse>()

        val token = response.result?.accessToken
            ?: throw ExternalServiceException("Augmont", "Login failed: ${response.message}")

        redisTemplate.opsForValue().set(REDIS_TOKEN_KEY, token, TOKEN_TTL).awaitSingle()
        log.info("Augmont: Login successful, token cached for 23h")
        return token
    }

    /**
     * Invalidates the cached token (used on 401 before retry).
     */
    private suspend fun invalidateToken() {
        redisTemplate.delete(REDIS_TOKEN_KEY).awaitSingle()
    }

    // ── Generic API Helpers ──
    // These are kept as `private suspend` + explicit Class<T> parameter because
    // `inline fun <reified T>` is not allowed on open (virtual) class members.
    // Callers in this file use the typed public wrappers below which are inlined
    // in the companion object.

    private suspend fun <T : Any> doGet(
        uri: String,
        queryParams: Map<String, String> = emptyMap(),
        retry: Boolean = true,
        clazz: Class<T>
    ): T {
        val token = getAccessToken()
        return try {
            webClient.get()
                .uri { builder ->
                    builder.path(uri)
                    queryParams.forEach { (k, v) -> builder.queryParam(k, v) }
                    builder.build()
                }
                .header(HttpHeaders.AUTHORIZATION, "Bearer $token")
                .retrieve()
                .bodyToMono(clazz).awaitSingle()
        } catch (ex: Exception) {
            if (retry && isAuthError(ex)) {
                log.warn("Augmont: 401 on GET {}, re-authenticating…", uri)
                invalidateToken()
                doGet(uri, queryParams, retry = false, clazz = clazz)
            } else {
                throw ExternalServiceException("Augmont", "GET $uri failed: ${ex.message}", ex)
            }
        }
    }

    private suspend fun <T : Any> doPost(
        uri: String,
        formFields: Map<String, String>,
        retry: Boolean = true,
        clazz: Class<T>
    ): T {
        val token = getAccessToken()
        val body = MultipartBodyBuilder().apply {
            formFields.forEach { (k, v) -> part(k, v) }
        }.build()

        return try {
            webClient.post()
                .uri(uri)
                .header(HttpHeaders.AUTHORIZATION, "Bearer $token")
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(BodyInserters.fromMultipartData(body))
                .retrieve()
                .bodyToMono(clazz).awaitSingle()
        } catch (ex: Exception) {
            if (retry && isAuthError(ex)) {
                log.warn("Augmont: 401 on POST {}, re-authenticating…", uri)
                invalidateToken()
                doPost(uri, formFields, retry = false, clazz = clazz)
            } else {
                throw ExternalServiceException("Augmont", "POST $uri failed: ${ex.message}", ex)
            }
        }
    }

    private suspend fun <T : Any> doPut(
        uri: String,
        formFields: Map<String, String>,
        retry: Boolean = true,
        clazz: Class<T>
    ): T {
        val token = getAccessToken()
        val body = MultipartBodyBuilder().apply {
            formFields.forEach { (k, v) -> part(k, v) }
        }.build()

        return try {
            webClient.put()
                .uri(uri)
                .header(HttpHeaders.AUTHORIZATION, "Bearer $token")
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(BodyInserters.fromMultipartData(body))
                .retrieve()
                .bodyToMono(clazz).awaitSingle()
        } catch (ex: Exception) {
            if (retry && isAuthError(ex)) {
                log.warn("Augmont: 401 on PUT {}, re-authenticating…", uri)
                invalidateToken()
                doPut(uri, formFields, retry = false, clazz = clazz)
            } else {
                throw ExternalServiceException("Augmont", "PUT $uri failed: ${ex.message}", ex)
            }
        }
    }

    fun isAuthError(ex: Exception): Boolean {
        val msg = ex.message ?: return false
        return "401" in msg || "Unauthorized" in msg
    }

    // ═══════════════════════════════════════════════════════════
    // High-level Augmont API Methods
    // ═══════════════════════════════════════════════════════════

    // ── Rates ──

    suspend fun getRates(): AugmontRatesResponse =
        doGet("/merchant/v1/rates", clazz = AugmontRatesResponse::class.java)

    // ── Buy ──

    suspend fun buy(request: AugmontBuyRequest): AugmontBuyResponse {
        val fields = mutableMapOf(
            "lockPrice" to request.lockPrice.toPlainString(),
            "metalType" to request.metalType,
            "blockId" to request.blockId,
            "uniqueId" to request.uniqueId,
            "merchantTransactionId" to request.merchantTransactionId,
            "modeOfPayment" to request.modeOfPayment
        )
        request.quantity?.let { fields["quantity"] = it.toPlainString() }
        request.amount?.let { fields["amount"] = it.toPlainString() }
        request.userName?.let { fields["userName"] = it }
        request.userEmail?.let { fields["userEmail"] = it }
        request.userMobile?.let { fields["userMobile"] = it }

        return doPost("/merchant/v1/buy", fields, clazz = AugmontBuyResponse::class.java)
    }

    suspend fun getBuyInfo(txnId: String): AugmontBuyInfoResponse =
        doGet("/merchant/v1/buy/$txnId", clazz = AugmontBuyInfoResponse::class.java)

    // ── Sell ──

    suspend fun sell(request: AugmontSellRequest): AugmontSellResponse {
        val fields = mutableMapOf(
            "lockPrice" to request.lockPrice.toPlainString(),
            "metalType" to request.metalType,
            "quantity" to request.quantity.toPlainString(),
            "blockId" to request.blockId,
            "uniqueId" to request.uniqueId,
            "merchantTransactionId" to request.merchantTransactionId,
            "modeOfPayment" to request.modeOfPayment
        )
        request.userName?.let { fields["userName"] = it }
        request.bankAccountId?.let { fields["bankAccountId"] = it }

        return doPost("/merchant/v1/sell", fields, clazz = AugmontSellResponse::class.java)
    }

    // ── User ──

    suspend fun createUser(request: AugmontCreateUserRequest): AugmontUserResponse {
        val fields = mutableMapOf(
            "userName" to request.userName,
            "userEmail" to request.userEmail,
            "userMobile" to request.userMobile
        )
        request.dateOfBirth?.let { fields["dateOfBirth"] = it }
        request.panNumber?.let { fields["panNumber"] = it }
        request.userPincode?.let { fields["userPincode"] = it }
        request.userAddress?.let { fields["userAddress"] = it }
        request.userCity?.let { fields["userCity"] = it }
        request.userState?.let { fields["userState"] = it }

        return doPost("/merchant/v1/users", fields, clazz = AugmontUserResponse::class.java)
    }

    suspend fun getUser(uniqueId: String): AugmontUserResponse =
        doGet("/merchant/v1/users/$uniqueId", clazz = AugmontUserResponse::class.java)

    // ── KYC ──

    suspend fun getKycStatus(uniqueId: String): AugmontKycResponse =
        doGet("/merchant/v1/users/$uniqueId/kyc", clazz = AugmontKycResponse::class.java)

    // ── Passbook ──

    suspend fun getPassbook(uniqueId: String): AugmontPassbookResponse =
        doGet("/merchant/v1/users/$uniqueId/passbook", clazz = AugmontPassbookResponse::class.java)

    // ── Bank ──

    suspend fun addBank(request: AugmontAddBankRequest): AugmontBankResponse {
        val fields = mapOf(
            "accountNumber" to request.accountNumber,
            "ifscCode" to request.ifscCode,
            "accountName" to request.accountName
        )
        return doPost("/merchant/v1/users/${request.uniqueId}/banks", fields, clazz = AugmontBankResponse::class.java)
    }

    suspend fun getBanks(uniqueId: String): AugmontBankResponse =
        doGet("/merchant/v1/users/$uniqueId/banks", clazz = AugmontBankResponse::class.java)

    // ── FD ──

    suspend fun getFdSchemes(): AugmontFdSchemesResponse =
        doGet("/merchant/v1/fd/schemes", clazz = AugmontFdSchemesResponse::class.java)

    suspend fun fdPreOrder(request: AugmontFdPreOrderRequest): AugmontFdPreOrderResponse {
        val fields = mapOf(
            "goldWeight" to request.goldWeight.toPlainString(),
            "tenure" to request.tenure.toString(),
            "schemeId" to request.schemeId
        )
        return doPost("/merchant/v1/fd/pre-order", fields, clazz = AugmontFdPreOrderResponse::class.java)
    }

    suspend fun createFd(request: AugmontFdCreateRequest): AugmontFdCreateResponse {
        val fields = mapOf(
            "goldWeight" to request.goldWeight.toPlainString(),
            "tenure" to request.tenure.toString(),
            "schemeId" to request.schemeId,
            "uniqueId" to request.uniqueId,
            "merchantTransactionId" to request.merchantTransactionId
        )
        return doPost("/merchant/v1/fd/create", fields, clazz = AugmontFdCreateResponse::class.java)
    }

    suspend fun getFdDetail(fdId: String): AugmontFdCreateResponse =
        doGet("/merchant/v1/fd/$fdId", clazz = AugmontFdCreateResponse::class.java)

    suspend fun preCloseFd(request: AugmontFdPreCloseRequest): AugmontFdPreCloseResponse {
        val fields = mapOf(
            "fdOrderId" to request.fdOrderId,
            "uniqueId" to request.uniqueId
        )
        return doPost("/merchant/v1/fd/pre-close", fields, clazz = AugmontFdPreCloseResponse::class.java)
    }

    // ── Historical / Rolling Data ──

    suspend fun getRollingData(
        metalType: String = "gold",
        duration: String = "1m"
    ): AugmontRollingDataResponse =
        doGet("/merchant/v1/rolling-data", mapOf("metalType" to metalType, "duration" to duration), clazz = AugmontRollingDataResponse::class.java)

    // ── Products ──

    suspend fun getProducts(): AugmontProductsResponse =
        doGet("/merchant/v1/products", clazz = AugmontProductsResponse::class.java)
}
