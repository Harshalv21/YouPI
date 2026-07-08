package `in`.youpi.payment.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.Result
import `in`.youpi.payment.domain.*
import `in`.youpi.payment.service.PaymentService
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
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.RequestMethod
import org.springframework.web.reactive.function.server.*

@Configuration
class PaymentRouter(private val paymentService: PaymentService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/payment/order", method = [RequestMethod.POST],
            operation = Operation(operationId = "createPaymentOrder", summary = "Create Razorpay order",
                description = "Creates a Razorpay payment order for the given purpose and amount.",
                tags = ["Payment"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = CreatePaymentOrderRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "201", description = "Razorpay order created")])),
        RouterOperation(path = "/v1/payment/verify", method = [RequestMethod.POST],
            operation = Operation(operationId = "verifyPayment", summary = "Verify Razorpay payment",
                description = "Verifies the Razorpay payment signature (HMAC-SHA256) and marks as captured.",
                tags = ["Payment"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = VerifyPaymentRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Payment verified")])),
        RouterOperation(path = "/webhooks/razorpay", method = [RequestMethod.POST],
            operation = Operation(operationId = "razorpayWebhook", summary = "Razorpay webhook handler",
                description = "Receives Razorpay webhook events. No authentication required. Uses HMAC signature verification.",
                tags = ["Payment"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Webhook processed")]))
    )
    fun paymentRoutes() = coRouter {
        "/v1/payment".nest {
            POST("/order") { handleCreateOrder(it) }
            POST("/verify") { handleVerifyPayment(it) }
        }
        POST("/webhooks/razorpay") { handleWebhook(it) }
    }

    private suspend fun handleCreateOrder(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<CreatePaymentOrderRequest>()
        return when (val result = paymentService.createOrder(userId, body)) {
            is Result.Success -> ServerResponse.status(201).contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.created(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleVerifyPayment(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<VerifyPaymentRequest>()
        return when (val result = paymentService.verifyPayment(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleWebhook(request: ServerRequest): ServerResponse {
        val rawBody = request.awaitBody<String>()
        val signature = request.headers().firstHeader("X-Razorpay-Signature") ?: ""
        val success = paymentService.handleWebhook(rawBody, signature)
        return if (success) {
            ServerResponse.ok().bodyValueAndAwait(mapOf("status" to "ok"))
        } else {
            ServerResponse.status(HttpStatus.UNAUTHORIZED).bodyValueAndAwait(mapOf("status" to "signature_invalid"))
        }
    }
}
