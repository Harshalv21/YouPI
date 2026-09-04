package `in`.youpi.recharge.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.awaitValidatedBody
import `in`.youpi.core.Result
import `in`.youpi.recharge.domain.RechargeApiException
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
 *  - GET .../dth/plans -- no DTH plan-listing API exists via A1Topup.
 *  - POST .../dth/validate -- no subscriber-ID validation API documented
 *    via A1Topup.
 * Add them the same way fetchPlans()/detectOperator() work in
 * RechargeRouter.kt if either turns out to exist.
 *
 * Customer-info lookup (GET .../dth/customer-info and
 * .../dth/customer-info-mobile below) IS implemented, but via mPlan --
 * NOT A1Topup. mPlan confirmed (Sep 2026) two separate DTH Customer Info
 * APIs: one keyed by subscriber/VC number, one by the customer's
 * registered mobile number. See DthRechargeService.fetchDthCustomerInfoByVc()/
 * fetchDthCustomerInfoByMobile() for the actual mPlan calls.
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
                responses = [SwaggerApiResponse(responseCode = "200", description = "Order status details")])),
        RouterOperation(path = "/v1/recharge/dth/customer-info", method = [RequestMethod.GET],
            operation = Operation(operationId = "getDthCustomerInfoByVc", summary = "Get DTH customer info by subscriber/VC number",
                description = "Looks up the DTH subscriber via mPlan by subscriber/VC number -- returns customer name, " +
                        "current monthly recharge amount, balance, next due date, and whether the connection is currently ACTIVE.",
                tags = ["DTH Recharge"],
                parameters = [
                    Parameter(name = "vcNumber", description = "Subscriber/VC number", required = true),
                    Parameter(name = "operator", description = "One of the SUPPORTED_DTH_OPERATORS names", required = true)
                ],
                responses = [SwaggerApiResponse(responseCode = "200", description = "DTH customer info")])),
        RouterOperation(path = "/v1/recharge/dth/customer-info-mobile", method = [RequestMethod.GET],
            operation = Operation(operationId = "getDthCustomerInfoByMobile", summary = "Get DTH customer info by registered mobile number",
                description = "Looks up the DTH subscriber via mPlan by their registered mobile number instead of subscriber/VC number.",
                tags = ["DTH Recharge"],
                parameters = [
                    Parameter(name = "mobileNumber", description = "Customer's registered mobile number", required = true),
                    Parameter(name = "operator", description = "One of the SUPPORTED_DTH_OPERATORS names", required = true)
                ],
                responses = [SwaggerApiResponse(responseCode = "200", description = "DTH customer info")]))
    )
    fun dthRoutes() = coRouter {
        "/v1/recharge/dth".nest {
            GET("/operators") { handleGetOperators(it) }
            POST("/order") { handleCreateOrder(it) }
            GET("/order/{orderId}") { handleGetOrderStatus(it) }
            GET("/customer-info") { handleGetCustomerInfoByVc(it) }
            GET("/customer-info-mobile") { handleGetCustomerInfoByMobile(it) }
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

    private suspend fun handleGetCustomerInfoByVc(request: ServerRequest): ServerResponse {
        // currentUserId() not needed for this read-only lookup -- kept
        // behind auth anyway (this route sits inside the coRouter that
        // FirebaseAuthFilter already gates) so an unauthenticated caller
        // can't probe arbitrary subscriber numbers for free.
        request.currentUserId()
        val vcNumber = request.queryParam("vcNumber")
            .orElseThrow { RechargeApiException("vcNumber is required") }
        val operator = request.queryParam("operator")
            .orElseThrow { RechargeApiException("operator is required") }
        return when (val result = dthRechargeService.fetchDthCustomerInfoByVc(vcNumber, operator)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleGetCustomerInfoByMobile(request: ServerRequest): ServerResponse {
        request.currentUserId()
        val mobileNumber = request.queryParam("mobileNumber")
            .orElseThrow { RechargeApiException("mobileNumber is required") }
        val operator = request.queryParam("operator")
            .orElseThrow { RechargeApiException("operator is required") }
        return when (val result = dthRechargeService.fetchDthCustomerInfoByMobile(mobileNumber, operator)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }
}