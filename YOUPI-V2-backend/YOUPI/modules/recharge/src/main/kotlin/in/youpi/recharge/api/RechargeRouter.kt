package `in`.youpi.recharge.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.Result
import `in`.youpi.recharge.domain.*
import `in`.youpi.recharge.service.RechargeService
import `in`.youpi.security.currentUserId
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
class RechargeRouter(private val rechargeService: RechargeService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/recharge/plans", method = [RequestMethod.GET],
            operation = Operation(operationId = "fetchPlans", summary = "Fetch recharge plans",
                description = "Fetches recharge plans from mPlan API for a given operator and circle. Results are cached for 30 minutes.",
                tags = ["Recharge"],
                parameters = [
                    Parameter(name = "operator", description = "Telecom operator (e.g. JIO, AIRTEL, VI)", required = false),
                    Parameter(name = "circle", description = "Service circle (e.g. UP-East, Delhi)", required = false)
                ],
                responses = [SwaggerApiResponse(responseCode = "200", description = "List of recharge plans")])),
        RouterOperation(path = "/v1/recharge/order", method = [RequestMethod.POST],
            operation = Operation(operationId = "createRechargeOrder", summary = "Create recharge order",
                description = "Creates a new recharge order with optional EMI payment mode. Returns Razorpay order ID.",
                tags = ["Recharge"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = CreateRechargeRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "201", description = "Order created with Razorpay order ID")])),
        RouterOperation(path = "/v1/recharge/order/{orderId}/confirm", method = [RequestMethod.POST],
            operation = Operation(operationId = "confirmRechargeOrder", summary = "Confirm recharge after payment",
                description = "Verifies Razorpay payment signature, marks the recharge as successful, and " +
                        "auto-invests a small percentage of the recharge amount into gold. Gold-invest failure " +
                        "does not fail the recharge — check goldWarning in the response.",
                tags = ["Recharge"],
                parameters = [Parameter(name = "orderId", description = "UUID of the recharge order", required = true)],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = ConfirmRechargeRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Recharge confirmed, with gold auto-invest outcome")])),
        RouterOperation(path = "/v1/recharge/order/{orderId}", method = [RequestMethod.GET],
            operation = Operation(operationId = "getOrderStatus", summary = "Get recharge order status",
                description = "Returns the current status of a recharge order including A1Topup processing status.",
                tags = ["Recharge"],
                parameters = [Parameter(name = "orderId", description = "UUID of the recharge order", required = true)],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Order status details")])),
        RouterOperation(path = "/v1/recharge/history", method = [RequestMethod.GET],
            operation = Operation(operationId = "getRechargeHistory", summary = "Get recharge history",
                description = "Returns paginated recharge order history for the authenticated user.",
                tags = ["Recharge"],
                parameters = [Parameter(name = "page", description = "Page number (0-based)", required = false)],
                responses = [SwaggerApiResponse(responseCode = "200", description = "List of past recharge orders")]))
    )
    fun rechargeRoutes() = coRouter {
        "/v1/recharge".nest {
            GET("/plans") { handleFetchPlans(it) }
            POST("/order") { handleCreateOrder(it) }
            POST("/order/{orderId}/confirm") { handleConfirmOrder(it) }
            GET("/order/{orderId}") { handleGetOrderStatus(it) }
            GET("/history") { handleHistory(it) }
        }
    }

    private suspend fun handleFetchPlans(request: ServerRequest): ServerResponse {
        val operator = request.queryParam("operator").orElse("JIO")
        val circle = request.queryParam("circle").orElse("UP-East")
        return when (val result = rechargeService.fetchPlans(operator, circle)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleCreateOrder(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<CreateRechargeRequest>()
        return when (val result = rechargeService.createOrder(userId, body)) {
            is Result.Success -> ServerResponse.status(201).contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.created(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleConfirmOrder(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<ConfirmRechargeRequest>()
        return when (val result = rechargeService.confirmRecharge(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleGetOrderStatus(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val orderId = java.util.UUID.fromString(request.pathVariable("orderId"))
        return when (val result = rechargeService.getOrderStatus(userId, orderId)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleHistory(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val page = request.queryParam("page").map { it.toInt() }.orElse(0)
        val history = rechargeService.getOrderHistory(userId, page)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(history))
    }
}