package `in`.youpi.bnpl.api

import `in`.youpi.bnpl.service.*
import `in`.youpi.core.ApiResponse
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
class BnplRouter(private val bnplService: BnplService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/bnpl/status", method = [RequestMethod.GET],
            operation = Operation(operationId = "getBnplStatus", summary = "Get BNPL status",
                description = "Returns the user's BNPL application status, account limits, and available credit.",
                tags = ["BNPL"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "BNPL status and limits")])),
        RouterOperation(path = "/v1/bnpl/apply/step1", method = [RequestMethod.POST],
            operation = Operation(operationId = "bnplStep1", summary = "BNPL Apply — Step 1: Personal details",
                description = "Submits personal details (employment type, income). Saved to Redis session (30 min TTL).",
                tags = ["BNPL"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = BnplStep1Request::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Step 1 saved to session")])),
        RouterOperation(path = "/v1/bnpl/apply/step2", method = [RequestMethod.POST],
            operation = Operation(operationId = "bnplStep2", summary = "BNPL Apply — Step 2: CIBIL consent",
                description = "Submits CIBIL consent. Triggers credit bureau check and auto-decision.",
                tags = ["BNPL"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = BnplStep2Request::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "CIBIL consent recorded")])),
        RouterOperation(path = "/v1/bnpl/apply/step3", method = [RequestMethod.POST],
            operation = Operation(operationId = "bnplStep3", summary = "BNPL Apply — Step 3: T&C acceptance",
                description = "Accepts terms and conditions. Submits final application for auto-decisioning.",
                tags = ["BNPL"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = BnplStep3Request::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Application submitted with decision")]))
    )
    fun bnplRoutes() = coRouter {
        "/v1/bnpl".nest {
            GET("/status") { handleStatus(it) }
            POST("/apply/step1") { handleStep1(it) }
            POST("/apply/step2") { handleStep2(it) }
            POST("/apply/step3") { handleStep3(it) }
        }
    }

    private suspend fun handleStatus(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val status = bnplService.getStatus(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(status))
    }

    private suspend fun handleStep1(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<BnplStep1Request>()
        return when (val result = bnplService.submitStep1(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(mapOf("message" to result.value)))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleStep2(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<BnplStep2Request>()
        return when (val result = bnplService.submitStep2(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(mapOf("message" to result.value)))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleStep3(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<BnplStep3Request>()
        return when (val result = bnplService.submitStep3(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }
}
