package `in`.youpi.recharge.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.awaitValidatedBody
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
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.RequestMethod
import org.springframework.web.reactive.function.server.*

@Configuration
class RechargeRouter(
    private val rechargeService: RechargeService,
    // Shared secret appended to the callback URL registered with A1Topup
    // (e.g. .../a1topup-callback?token=<this value>). A1Topup's callback
    // has NO other authentication (no JWT -- they hit it directly, not
    // through the app -- and no HMAC signature like Razorpay's webhook
    // provides). Without this check, anyone who knows/observes a live
    // orderId (e.g. their own, from the app's own order-creation response)
    // could forge a "Success" callback for it directly and skip real
    // A1Topup fulfillment entirely -- see resolveA1TopupOutcome()'s
    // `order.status != "PENDING_VERIFICATION"` guard, which only blocks
    // RE-processing an already-finalized order, not a FIRST forged call.
    // MUST be set in Cloud Run env (youpi.a1topup.callback-token) to a
    // long random value, and that exact value included in the callback
    // URL given to A1Topup when registering it on their dashboard.
    @org.springframework.beans.factory.annotation.Value("\${youpi.a1topup.callback-token:}")
    private val a1topupCallbackToken: String,
) {
    private val log = LoggerFactory.getLogger(javaClass)

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
        RouterOperation(path = "/v1/recharge/operator", method = [RequestMethod.GET],
            operation = Operation(operationId = "detectOperator", summary = "Detect operator/circle from mobile number",
                description = "Uses mPlan's HLR/Operator Check API to detect a mobile number's real operator and circle. " +
                        "Returns values already normalized to match operatorCodeMap/circleCodeMap (e.g. \"JIO\", \"UP EAST\").",
                tags = ["Recharge"],
                parameters = [
                    Parameter(name = "mobile", description = "10-digit mobile number", required = true)
                ],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Detected operator and circle")])),
        RouterOperation(path = "/v1/recharge/order", method = [RequestMethod.POST],
            operation = Operation(operationId = "createRechargeOrder", summary = "Create recharge order",
                description = "Creates a new recharge order with optional EMI payment mode. Returns Razorpay order ID.",
                tags = ["Recharge"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = CreateRechargeRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "201", description = "Order created with Razorpay order ID")])),
        RouterOperation(path = "/v1/recharge/order/{orderId}/confirm", method = [RequestMethod.POST],
            operation = Operation(operationId = "confirmRechargeOrder", summary = "Check recharge order status (post-checkout)",
                description = "Reports the recharge order's CURRENT state after Razorpay Checkout closes. " +
                        "Does NOT verify a signature or mutate order state anymore — SUCCESS + gold auto-invest are " +
                        "granted only by the Razorpay webhook (POST /webhooks/razorpay), which is the sole trusted " +
                        "source for payment confirmation. If the order still shows INITIATED here, poll again after " +
                        "a few seconds; the webhook is usually near-instant but isn't guaranteed to beat this call.",
                tags = ["Recharge"],
                parameters = [Parameter(name = "orderId", description = "UUID of the recharge order", required = true)],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = ConfirmRechargeRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Current order status, with gold auto-invest outcome if already SUCCESS")])),
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
                responses = [SwaggerApiResponse(responseCode = "200", description = "List of past recharge orders")])),
        RouterOperation(path = "/v1/recharge/active", method = [RequestMethod.GET],
            operation = Operation(operationId = "getActiveRecharge", summary = "Get current active recharge",
                description = "Returns the user's currently active (not-yet-expired) recharge for the home screen status card, or null if none.",
                tags = ["Recharge"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Active recharge, or null")])),
        RouterOperation(path = "/v1/recharge/active/all", method = [RequestMethod.GET],
            operation = Operation(operationId = "getActiveRecharges", summary = "Get all current active recharges",
                description = "Returns ALL of the user's currently active (not-yet-expired) recharges, soonest-expiring first, for the home screen's horizontally-scrollable Active Recharge strip.",
                tags = ["Recharge"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "List of active recharges (may be empty)")]))
    )
    fun rechargeRoutes() = coRouter {
        "/v1/recharge".nest {
            GET("/plans") { handleFetchPlans(it) }
            GET("/operator") { handleDetectOperator(it) }
            POST("/order") { handleCreateOrder(it) }
            POST("/order/{orderId}/confirm") { handleConfirmOrder(it) }
            GET("/order/{orderId}") { handleGetOrderStatus(it) }
            GET("/history") { handleHistory(it) }
            GET("/active") { handleGetActiveRecharge(it) }
            GET("/active/all") { handleGetActiveRecharges(it) }
        }
        // A1Topup's callback -- hit directly BY A1TOPUP, not by our app, so
        // no JWT is sent. This path MUST be added to the security config's
        // public/unauthenticated allowlist (same way POST /webhooks/razorpay
        // presumably already is) -- otherwise the JWT auth filter will
        // reject A1Topup's callback before it ever reaches this handler.
        // GET+POST both wired since A1Topup's own docs say they may use
        // either for this.
        "/v1/webhooks/a1topup-callback".let { path ->
            GET(path) { handleA1TopupCallback(it) }
            POST(path) { handleA1TopupCallback(it) }
        }
    }

    /**
     * A1Topup calls this with query params txid (= our orderid), status
     * (Success/Failure), opid (operator transaction id, or failure reason
     * text). See A1TopupClient.kt / RechargeService.handleA1TopupCallback
     * for the resolution logic this triggers.
     */
    private suspend fun handleA1TopupCallback(request: ServerRequest): ServerResponse {
        // Fail closed: an unconfigured secret must never mean "accept
        // anything" -- same fail-closed principle already used for the
        // Razorpay HMAC secret in PaymentService.kt.
        if (a1topupCallbackToken.isBlank()) {
            log.error("A1Topup callback rejected: youpi.a1topup.callback-token is not configured")
            return ServerResponse.status(org.springframework.http.HttpStatus.FORBIDDEN)
                .bodyValueAndAwait("callback not configured")
        }
        val providedToken = request.queryParam("token").orElse("")
        if (!java.security.MessageDigest.isEqual(
                providedToken.toByteArray(), a1topupCallbackToken.toByteArray()
            )
        ) {
            log.warn("A1Topup callback rejected: invalid or missing token (from {})", request.remoteAddress().orElse(null))
            return ServerResponse.status(org.springframework.http.HttpStatus.FORBIDDEN)
                .bodyValueAndAwait("invalid token")
        }

        val orderId = request.queryParam("txid").orElse(null)
        val status = request.queryParam("status").orElse(null)
        val opid = request.queryParam("opid").orElse(null)

        if (orderId == null || status == null) {
            // Don't throw -- A1Topup doesn't care about our error format
            // and retrying a malformed callback won't help. Just log and
            // ack so they don't keep retrying a call we can't parse.
            return ServerResponse.ok().bodyValueAndAwait("ignored: missing txid/status")
        }

        rechargeService.handleA1TopupCallback(orderId, status, opid)
        // A1Topup just needs a 200 to consider the callback delivered --
        // doesn't parse the body.
        return ServerResponse.ok().bodyValueAndAwait("ok")
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

    private suspend fun handleDetectOperator(request: ServerRequest): ServerResponse {
        val mobile = request.queryParam("mobile").orElseThrow {
            RechargeApiException("Missing required query param: mobile")
        }
        return when (val result = rechargeService.detectOperator(mobile)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleCreateOrder(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitValidatedBody<CreateRechargeRequest>()
        return when (val result = rechargeService.createOrder(userId, body)) {
            is Result.Success -> ServerResponse.status(201).contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.created(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleConfirmOrder(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitValidatedBody<ConfirmRechargeRequest>()
        // This no longer mutates order state (see RechargeService docs) --
        // the Razorpay webhook is the only writer now. This just reports
        // whatever the webhook has already recorded, so the app can show
        // the right screen right after checkout closes.
        return when (val result = rechargeService.getConfirmationStatus(userId, body.rechargeOrderId)) {
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

    private suspend fun handleGetActiveRecharge(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val active = rechargeService.getActiveRecharge(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(active))
    }

    private suspend fun handleGetActiveRecharges(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val active = rechargeService.getActiveRecharges(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(active))
    }
}