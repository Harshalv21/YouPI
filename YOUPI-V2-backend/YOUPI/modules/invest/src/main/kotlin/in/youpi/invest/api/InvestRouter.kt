package `in`.youpi.invest.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.Result
import `in`.youpi.invest.service.InvestService
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

import `in`.youpi.invest.api.request.BuyGoldRequest
import `in`.youpi.invest.api.request.SellGoldRequest
import `in`.youpi.invest.api.request.CreateAugmontUserRequest

import java.math.BigDecimal

@Configuration
class InvestRouter(private val investService: InvestService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/gold/price", method = [RequestMethod.GET],
            operation = Operation(operationId = "getGoldPrice", summary = "Get live gold & silver rates",
                description = "Returns live gold/silver buy+sell rates from Augmont API. Cached for 35 seconds. Returns blockId needed for buy/sell.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Current rates with blockId")])),
        RouterOperation(path = "/v1/gold/holdings", method = [RequestMethod.GET],
            operation = Operation(operationId = "getGoldHoldings", summary = "Get gold holdings",
                description = "Returns the user's total digital gold holdings in grams and current INR value.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Gold holdings")])),
        RouterOperation(path = "/v1/gold/buy", method = [RequestMethod.POST],
            operation = Operation(
                operationId = "buyGold",
                summary = "Buy digital gold/silver",
                description = "Purchases digital gold/silver for the given amount in INR via Augmont. Idempotent via idempotencyKey. Uses locked blockId and rate.",
                tags = ["Gold"],

                requestBody = SwaggerRequestBody(
                    content = [
                        Content(
                            schema = Schema(
                                implementation = BuyGoldRequest::class
                            ))]),

                responses = [
                    SwaggerApiResponse(
                        responseCode = "201",
                        description = "Gold purchase confirmation"
                    )])),
        RouterOperation(path = "/v1/gold/sell", method = [RequestMethod.POST],
            operation = Operation(
                operationId = "sellGold",
                summary = "Sell digital gold/silver",
                description = "Sells digital gold/silver by grams via Augmont. Payout to user's bank account.",
                tags = ["Gold"],

                requestBody = SwaggerRequestBody(
                    content = [
                        Content(
                            schema = Schema(
                                implementation = SellGoldRequest::class
                            ))]),

                responses = [
                    SwaggerApiResponse(
                        responseCode = "201",
                        description = "Gold sell confirmation"
                    )])),
        RouterOperation(path = "/v1/gold/passbook", method = [RequestMethod.GET],
            operation = Operation(operationId = "getPassbook", summary = "Get Augmont passbook",
                description = "Returns the user's real gold/silver balance directly from Augmont.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Augmont passbook")])),
        RouterOperation(path = "/v1/gold/history", method = [RequestMethod.GET],
            operation = Operation(operationId = "getPriceHistory", summary = "Get price history",
                description = "Returns historical gold/silver price data for chart rendering. Supports durations: 1d, 1w, 1m, 3m, 6m, 1y.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Price history")])),
        RouterOperation(path = "/v1/gold/products", method = [RequestMethod.GET],
            operation = Operation(operationId = "getProducts", summary = "List physical gold products",
                description = "Returns available physical gold/silver products (coins, bars) for redemption.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Product list")])),
        RouterOperation(path = "/v1/gold/transactions", method = [RequestMethod.GET],
            operation = Operation(operationId = "getTransactions", summary = "Get gold transaction history",
                description = "Returns the user's gold buy/sell transaction history.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Transaction list")])),
        RouterOperation(path = "/v1/gold/kyc", method = [RequestMethod.GET],
            operation = Operation(operationId = "getKycStatus", summary = "Get Augmont KYC status",
                description = "Returns the user's KYC verification status on Augmont.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "KYC status")])),
        RouterOperation(path = "/v1/gold/user", method = [RequestMethod.POST],
            operation = Operation(operationId = "createAugmontUser", summary = "Create Augmont user mapping",
                description = "Creates a user on Augmont and maps them to the YouPI user. Must be called before buy/sell.",
                tags = ["Gold"],
                responses = [SwaggerApiResponse(responseCode = "201", description = "User mapping created")])),
        RouterOperation(path = "/v1/fd/schemes", method = [RequestMethod.GET],
            operation = Operation(operationId = "getFdSchemes", summary = "List Gold FD schemes",
                description = "Returns available Gold FD schemes from Augmont.",
                tags = ["Gold FD"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "FD schemes")])),
        RouterOperation(path = "/v1/fd/preview", method = [RequestMethod.POST],
            operation = Operation(operationId = "previewFd", summary = "Preview Gold FD interest",
                description = "Calculates expected interest and maturity for a Gold FD based on weight, tenure, and scheme.",
                tags = ["Gold FD"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "FD preview")])),
        RouterOperation(path = "/v1/fd/create", method = [RequestMethod.POST],
            operation = Operation(operationId = "createFd", summary = "Create Gold FD",
                description = "Creates a new Gold Fixed Deposit on Augmont.",
                tags = ["Gold FD"],
                responses = [SwaggerApiResponse(responseCode = "201", description = "Gold FD created")])),
        RouterOperation(path = "/v1/fd/{id}", method = [RequestMethod.GET],
            operation = Operation(operationId = "getFdDetail", summary = "Get Gold FD details",
                description = "Returns details of a specific Gold FD by its Augmont ID.",
                tags = ["Gold FD"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "FD details")])),
        RouterOperation(path = "/v1/fd/{id}/close", method = [RequestMethod.POST],
            operation = Operation(operationId = "closeFd", summary = "Pre-close Gold FD",
                description = "Initiates early closure of a Gold FD.",
                tags = ["Gold FD"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "FD close result")])),
        RouterOperation(path = "/v1/fd/list", method = [RequestMethod.GET],
            operation = Operation(operationId = "listFixedDeposits", summary = "List fixed deposits",
                description = "Returns all legacy fixed deposits for the authenticated user.",
                tags = ["Fixed Deposit"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "List of FDs")]))
    )
    fun investRoutes() = coRouter {
        "/v1".nest {
            // ── Gold / Silver ──
            GET("/gold/price") { handleGoldPrice(it) }
            GET("/gold/holdings") { handleGoldHoldings(it) }
            POST("/gold/buy") { handleGoldBuy(it) }
            POST("/gold/sell") { handleGoldSell(it) }
            GET("/gold/passbook") { handlePassbook(it) }
            GET("/gold/history") { handlePriceHistory(it) }
            GET("/gold/products") { handleProducts(it) }
            GET("/gold/transactions") { handleTransactions(it) }
            GET("/gold/kyc") { handleKycStatus(it) }
            POST("/gold/user") { handleCreateAugmontUser(it) }

            // ── Gold FD ──
            GET("/fd/schemes") { handleFdSchemes(it) }
            POST("/fd/preview") { handleFdPreview(it) }
            POST("/fd/create") { handleFdCreate(it) }
            GET("/fd/{id}") { handleFdDetail(it) }
            POST("/fd/{id}/close") { handleFdClose(it) }

            // ── Legacy FDs ──
            GET("/fd/list") { handleFdList(it) }
        }
    }

    // ══════════════════════════════════════
    // Gold/Silver Handlers
    // ══════════════════════════════════════

    private suspend fun handleGoldPrice(request: ServerRequest): ServerResponse {
        return when (val result = investService.getLiveRates()) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleGoldHoldings(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val holdings = investService.getHoldings(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(holdings))
    }

    private suspend fun handleGoldBuy(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<BuyGoldRequest>()
        return when (
            val result = investService.buyGold(
                userId = userId,
                amountInr = body.amount,
                idempotencyKey = body.idempotencyKey,
                metalType = body.metalType
            )) {
            is Result.Success -> ServerResponse.status(201)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.created(result.value))
            is Result.Failure -> throw result.error
        }}

    private suspend fun handleGoldSell(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<SellGoldRequest>()
        return when (
            val result = investService.sellGold(
                userId = userId,
                grams = body.grams,
                idempotencyKey = body.idempotencyKey,
                metalType = body.metalType,
                bankAccountId = body.bankAccountId
            )) {
            is Result.Success ->ServerResponse.status(201)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.created(result.value))
            is Result.Failure -> throw result.error
        }}

    private suspend fun handlePassbook(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val passbook = investService.getPassbook(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(passbook))
    }

    private suspend fun handlePriceHistory(request: ServerRequest): ServerResponse {
        val metalType = request.queryParam("metalType").orElse("gold")
        val duration = request.queryParam("duration").orElse("1m")
        val history = investService.getPriceHistory(metalType, duration)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(history))
    }

    private suspend fun handleProducts(request: ServerRequest): ServerResponse {
        val products = investService.getProducts()
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(products))
    }

    private suspend fun handleTransactions(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val limit = request.queryParam("limit").map { it.toIntOrNull() ?: 20 }.orElse(20)
        val txns = investService.getTransactions(userId, limit)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(txns))
    }

    private suspend fun handleKycStatus(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val kyc = investService.getKycStatus(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(kyc))
    }

    private suspend fun handleCreateAugmontUser(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<CreateAugmontUserRequest>()
        val uniqueId =
            investService.ensureAugmontUser(
                userId = userId,
                userName = body.userName,
                userEmail = body.userEmail,
                userMobile = body.userMobile
            )
        return ServerResponse.status(201).contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.created(mapOf("augmontUniqueId" to uniqueId)))
    }

    // ══════════════════════════════════════
    // Gold FD Handlers
    // ══════════════════════════════════════

    private suspend fun handleFdSchemes(request: ServerRequest): ServerResponse {
        val schemes = investService.getGoldFdSchemes()
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(schemes))
    }

    private suspend fun handleFdPreview(request: ServerRequest): ServerResponse {
        val body = request.awaitBody<Map<String, Any>>()
        val goldWeight = BigDecimal(body["goldWeight"].toString())
        val tenure = body["tenure"].toString().toInt()
        val schemeId = body["schemeId"].toString()
        val preview = investService.previewGoldFd(goldWeight, tenure, schemeId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(preview))
    }

    private suspend fun handleFdCreate(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<Map<String, Any>>()
        val goldWeight = BigDecimal(body["goldWeight"].toString())
        val tenure = body["tenure"].toString().toInt()
        val schemeId = body["schemeId"].toString()
        val fdOrder = investService.createGoldFd(userId, goldWeight, tenure, schemeId)
        return ServerResponse.status(201).contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.created(fdOrder))
    }

    private suspend fun handleFdDetail(request: ServerRequest): ServerResponse {
    val userId = request.currentUserId()
    val fdId = request.pathVariable("id")
    val detail = investService.getGoldFdDetail(userId, fdId)
    return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
        .bodyValueAndAwait(ApiResponse.ok(detail))
}

    private suspend fun handleFdClose(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val fdId = request.pathVariable("id")
        val result = investService.closeGoldFd(userId, fdId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(result))
    }

    // ══════════════════════════════════════
    // Legacy FD Handler
    // ══════════════════════════════════════

    private suspend fun handleFdList(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val fds = investService.getFds(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(fds))
    }
}