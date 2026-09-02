package `in`.youpi.recharge.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.awaitValidatedBody
import `in`.youpi.core.Result
import `in`.youpi.recharge.domain.dth.CreateDthRechargeRequest
import `in`.youpi.recharge.domain.dth.SUPPORTED_DTH_OPERATORS
import `in`.youpi.recharge.service.DthRechargeService
import `in`.youpi.security.currentUserId
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.media.Content
import io.swagger.v3.oas.annotations.media.Schema
import io.swagger.v3.oas.annotations.parameters.RequestBody as SwaggerRequestBody
import io.swagger.v3.oas.annotations.responses.ApiResponse as SwaggerApiResponse
import org.springdoc.core.annotations.RouterOperation
import org.springdoc.core.annotations.RouterOperations
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.RequestMethod
import org.springframework.web.reactive.function.server.*

/**
 * DTH recharge routes -- a SEPARATE @Configuration/coRouter bean from
 * RechargeRouter (not added as nest{} entries inside it). Spring merges
 * multiple RouterFunction beans automatically, so this still serves
 * alongside routes under /v1/recharge with zero extra wiring -- RechargeRouter.kt
 * itself is untouched.
 *
 * NOT implemented (per A1Topup's docs, the one PDF provided):
 *  - GET .../dth/plans -- no DTH plan-listing API exists.
 *  - POST .../dth/validate -- no subscriber-ID validation API documented.
 * Add them the same way fetchPlans()/detectOperator() work in
 * RechargeRouter.kt if either turns out to exist.
 */
@Configuration
class DthRouter(
    private val dthRechargeService: DthRechargeService
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/recharge/dth/operators", method = [RequestMethod.GET],
            operation = Operation(operationId = "getDthOperators", summary = "Get supported DTH operators",
                description = "Static list of DTH operators A1Topup supports (Airtel Digital TV, Sun Direct, Tata Play, Videocon d2h, Dish TV). " +
                        "Not fetched live -- A1Topup exposes no DTH-operator-listing API.",
                tags = ["DTH Recharge"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "List of supported DTH operators")])),
        RouterOperation(path = "/v1/recharge/dth/order", method = [RequestMethod.POST],
            operation = Operation(operationId = "createDthOrder", summary = "Create DTH recharge order",
                description = "Creates a new DTH recharge order for the given subscriber/VC number and amount. " +
                        "Supports WALLET (synchronous) and FULL (Razorpay gateway) payment modes only.",
                tags = ["DTH Recharge"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = CreateDthRechargeRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "201", description = "Order created")])),
        RouterOperation(path = "/v1/recharge/dth/order/{orderId}", method = [RequestMethod.GET],
            operation = Operation(operationId = "getDthOrderStatus", summary = "Get DTH recharge order status",
                description = "Returns the current status of a DTH recharge order including A1Topup processing status.",
                tags = ["DTH Recharge"],
                parameters = [Parameter(name = "orderId", description = "UUID of the DTH recharge order", required = true)],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Order status details")]))
    )
    fun dthRoutes() = coRouter {
        "/v1/recharge/dth".nest {
            GET("/operators") { handleGetOperators(it) }
            POST("/order") { handleCreateOrder(it) }
            GET("/order/{orderId}") { handleGetOrderStatus(it) }
        }
    }

    private suspend fun handleGetOperators(request: ServerRequest): ServerResponse {
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(SUPPORTED_DTH_OPERATORS))
    }

    private suspend fun handleCreateOrder(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitValidatedBody<CreateDthRechargeRequest>()
        return when (val result = dthRechargeService.createOrder(userId, body)) {
            is Result.Success -> ServerResponse.status(201).contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.created(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleGetOrderStatus(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val orderId = java.util.UUID.fromString(request.pathVariable("orderId"))
        return when (val result = dthRechargeService.getOrderStatus(userId, orderId)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }
}   