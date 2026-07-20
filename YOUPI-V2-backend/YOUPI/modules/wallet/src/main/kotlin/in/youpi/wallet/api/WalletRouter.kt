package `in`.youpi.wallet.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.Result
import `in`.youpi.security.currentUserId
import `in`.youpi.wallet.service.*
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
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
class WalletRouter(private val walletService: WalletService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/wallet/balance", method = [RequestMethod.GET],
            operation = Operation(operationId = "getWalletBalance", summary = "Get wallet balances",
                description = "Returns all wallet balances (NBFC, Smart Saver, Gold, FD Collateral) for the user.",
                tags = ["Wallet"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "All wallet balances")])),
        RouterOperation(path = "/v1/wallet/ledger", method = [RequestMethod.GET],
            operation = Operation(operationId = "getWalletLedger", summary = "Get wallet ledger",
                description = "Returns the double-entry ledger (transaction history) for a specific wallet.",
                tags = ["Wallet"],
                parameters = [
                    Parameter(name = "type", description = "Wallet type: NBFC, SMART_SAVER, GOLD, FD_COLLATERAL", required = false),
                    Parameter(name = "page", description = "Page number (0-based)", required = false)
                ],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Ledger entries")])),
        RouterOperation(path = "/v1/wallet/transfer", method = [RequestMethod.POST],
            operation = Operation(operationId = "p2pTransfer", summary = "P2P wallet transfer",
                description = "Transfers funds from your NBFC wallet to another user by mobile number. Idempotent.",
                tags = ["Wallet"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = TransferRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Transfer successful")])),
        RouterOperation(path = "/v1/wallet/topup/order", method = [RequestMethod.POST],
            operation = Operation(operationId = "createWalletTopupOrder", summary = "Create wallet topup order",
                description = "Creates a real Razorpay order for adding money to the NBFC wallet.",
                tags = ["Wallet"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = CreateWalletTopupOrderRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Order created")]))
    )
    fun walletRoutes() = coRouter {
        "/v1/wallet".nest {
            GET("/balance") { handleBalance(it) }
            GET("/ledger") { handleLedger(it) }
            POST("/transfer") { handleTransfer(it) }
            POST("/topup/order") { handleCreateTopupOrder(it) }
        }
    }

    private suspend fun handleBalance(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val balance = walletService.getBalance(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(balance))
    }

    private suspend fun handleLedger(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val walletType = request.queryParam("type").orElse("NBFC")
        val page = request.queryParam("page").map { it.toInt() }.orElse(0)
        val entries = walletService.getLedger(userId, walletType, page)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(entries))
    }

    private suspend fun handleTransfer(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<TransferRequest>()
        // ← ab walletService.transfer() call hoga — debit + credit dono ek saath
        return when (val result = walletService.transfer(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    // ← NAYA: wallet topup order creation
    private suspend fun handleCreateTopupOrder(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<CreateWalletTopupOrderRequest>()
        return when (val result = walletService.createTopupOrder(userId, body.amountRupees)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }
}