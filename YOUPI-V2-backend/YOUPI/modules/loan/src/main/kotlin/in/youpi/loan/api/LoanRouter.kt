package `in`.youpi.loan.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.Result
import `in`.youpi.loan.service.*
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
import java.math.BigDecimal

@Configuration
class LoanRouter(private val loanService: LoanService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/loan/status", method = [RequestMethod.GET],
            operation = Operation(operationId = "getLoanStatus", summary = "Get loan status",
                description = "Returns the user's loan application status, approved amount, and account details.",
                tags = ["Loan"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Loan status")])),
        RouterOperation(path = "/v1/loan/apply/step1", method = [RequestMethod.POST],
            operation = Operation(operationId = "loanStep1", summary = "Loan Apply — Step 1: Personal info",
                description = "Submits personal info (name, DOB, PAN, address). Saved to Redis session.",
                tags = ["Loan"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = LoanStep1Request::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Step 1 saved")])),
        RouterOperation(path = "/v1/loan/apply/step2", method = [RequestMethod.POST],
            operation = Operation(operationId = "loanStep2", summary = "Loan Apply — Step 2: Employment & documents",
                description = "Submits employment details, income, and KYC documents.",
                tags = ["Loan"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = LoanStep2Request::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Step 2 saved")])),
        RouterOperation(path = "/v1/loan/apply/step3", method = [RequestMethod.POST],
            operation = Operation(operationId = "loanStep3", summary = "Loan Apply — Step 3: Final submission",
                description = "Submits CIBIL consent and loan amount. Triggers auto-decision and EMI calculation.",
                tags = ["Loan"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = LoanStep3Request::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Application decision")])),
        RouterOperation(path = "/v1/loan/emi/schedule", method = [RequestMethod.GET],
            operation = Operation(operationId = "getEmiSchedule", summary = "Get EMI schedule",
                description = "Returns the full EMI schedule for an active loan account.",
                tags = ["Loan"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "EMI schedule")])),
        RouterOperation(path = "/v1/loan/emi/calculate", method = [RequestMethod.GET],
            operation = Operation(operationId = "calculateEmi", summary = "EMI calculator",
                description = "Calculates monthly EMI for given principal, rate, and tenure using reducing balance formula.",
                tags = ["Loan"],
                parameters = [
                    Parameter(name = "principal", description = "Loan principal amount", required = false),
                    Parameter(name = "rate", description = "Annual interest rate (%)", required = false),
                    Parameter(name = "tenure", description = "Tenure in months", required = false)
                ],
                responses = [SwaggerApiResponse(responseCode = "200", description = "EMI calculation result")]))
    )
    fun loanRoutes() = coRouter {
        "/v1/loan".nest {
            GET("/status") { handleStatus(it) }
            POST("/apply/step1") { handleStep1(it) }
            POST("/apply/step2") { handleStep2(it) }
            POST("/apply/step3") { handleStep3(it) }
            GET("/emi/schedule") { handleEmiSchedule(it) }
            GET("/emi/calculate") { handleEmiCalculate(it) }
        }
    }

    private suspend fun handleStatus(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val status = loanService.getStatus(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(status))
    }

    private suspend fun handleStep1(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<LoanStep1Request>()
        return when (val result = loanService.submitStep1(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(mapOf("message" to result.value)))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleStep2(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<LoanStep2Request>()
        return when (val result = loanService.submitStep2(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(mapOf("message" to result.value)))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleStep3(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<LoanStep3Request>()
        return when (val result = loanService.submitStep3(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleEmiSchedule(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val schedule = loanService.getEmiSchedule(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(schedule))
    }

    private suspend fun handleEmiCalculate(request: ServerRequest): ServerResponse {
        val principal = BigDecimal(request.queryParam("principal").orElse("100000"))
        val rate = BigDecimal(request.queryParam("rate").orElse("12.0"))
        val tenure = request.queryParam("tenure").orElse("12").toShort()
        val result = loanService.calculateEmi(principal, rate, tenure)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(result))
    }
}
