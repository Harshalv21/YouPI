package `in`.youpi.gold

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.awaitValidatedBody
import `in`.youpi.core.Result
import `in`.youpi.security.currentUserId
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.media.Content
import io.swagger.v3.oas.annotations.media.Schema
import io.swagger.v3.oas.annotations.parameters.RequestBody as SwaggerRequestBody
import io.swagger.v3.oas.annotations.responses.ApiResponse as SwaggerApiResponse
import org.springdoc.core.annotations.RouterOperation
import org.springdoc.core.annotations.RouterOperations
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.RequestMethod
import org.springframework.web.reactive.function.server.*

@Configuration
class GoldRouter(
    private val goldWalletRepo: GoldWalletRepository,
    private val goldWithdrawService: GoldWithdrawService
) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/gold/wallet", method = [RequestMethod.GET],
            operation = Operation(operationId = "getGoldWallet", summary = "Get gold coin wallet balance",
                description = "Returns the user's current gold coin count and rupee value.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Gold wallet balance")])),
        RouterOperation(path = "/v1/gold/withdraw", method = [RequestMethod.POST],
            operation = Operation(operationId = "withdrawGold", summary = "Withdraw gold coin value as cash",
                description = "Converts gold coin rupee balance to cash and credits the NBFC wallet. Minimum ₹50.",
                tags = ["Gold"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = GoldWithdrawRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Withdraw successful")]))
    )
    fun goldRoutes() = coRouter {
        "/v1/gold".nest {
            GET("/wallet") { handleGetWallet(it) }
            POST("/withdraw") { handleWithdraw(it) }
        }
    }

    private suspend fun handleGetWallet(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val wallet = goldWalletRepo.findByUserId(userId)
        val coinCount = wallet?.coinCount ?: 0
        val balanceRupees = wallet?.balanceRupees ?: java.math.BigDecimal.ZERO
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(mapOf(
                "userId" to userId,
                "coinCount" to coinCount,
                "balanceRupees" to balanceRupees
            )))
    }

    private suspend fun handleWithdraw(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitValidatedBody<GoldWithdrawRequest>()
        return when (val result = goldWithdrawService.withdraw(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }
}