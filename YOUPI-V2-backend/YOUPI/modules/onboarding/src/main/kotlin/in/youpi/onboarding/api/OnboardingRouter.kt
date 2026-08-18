package `in`.youpi.onboarding.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.onboarding.service.OnboardingService
import `in`.youpi.onboarding.service.SubmitOnboardingRequest
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
class OnboardingRouter(private val onboardingService: OnboardingService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/onboarding/answers", method = [RequestMethod.POST],
            operation = Operation(operationId = "submitOnboardingAnswers", summary = "Submit onboarding answers",
                description = "Saves the 5-question financial profile for the logged-in user. Re-submitting a question overwrites the previous answer.",
                tags = ["Onboarding"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = SubmitOnboardingRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Answers saved")])),
        RouterOperation(path = "/v1/onboarding/answers", method = [RequestMethod.GET],
            operation = Operation(operationId = "getOnboardingAnswers", summary = "Get onboarding answers",
                description = "Returns whatever onboarding answers the logged-in user has saved so far.",
                tags = ["Onboarding"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Saved answers")]))
    )
    fun onboardingRoutes() = coRouter {
        "/v1/onboarding".nest {
            POST("/answers") { handleSubmit(it) }
            GET("/answers") { handleGet(it) }
        }
    }

    private suspend fun handleSubmit(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<SubmitOnboardingRequest>()
        onboardingService.submit(userId, body)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(mapOf("saved" to true)))
    }

    private suspend fun handleGet(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val answers = onboardingService.get(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(answers))
    }
}