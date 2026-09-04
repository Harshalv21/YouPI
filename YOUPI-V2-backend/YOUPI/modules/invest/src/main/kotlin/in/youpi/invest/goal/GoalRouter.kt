package `in`.youpi.invest.goal

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.awaitValidatedBody
import `in`.youpi.invest.api.request.CreateGoalRequest
import `in`.youpi.invest.api.request.TopupGoalRequest
import `in`.youpi.invest.api.request.UpdateGoalRequest
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

import java.util.UUID

@Configuration
class GoalRouter(
    private val goalService: GoalService,
    // Shared secret for the internal scheduler-trigger endpoint (Google
    // Cloud Scheduler is configured to send this in a header). NOT a
    // user-facing credential -- separate from JWT auth entirely.
    @org.springframework.beans.factory.annotation.Value("\${youpi.internal.gold-sip-secret:}")
    private val internalSecret: String
) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/gold/goals", method = [RequestMethod.POST],
            operation = Operation(operationId = "createGoal", summary = "Create a Gold SIP goal",
                description = "Creates a goal-based recurring gold investment plan.",
                tags = ["Gold Goals"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = CreateGoalRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "201", description = "Goal created")])),
        RouterOperation(path = "/v1/gold/goals", method = [RequestMethod.GET],
            operation = Operation(operationId = "listGoals", summary = "List goals",
                description = "Returns the user's active and completed goals.",
                tags = ["Gold Goals"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Goal list")])),
        RouterOperation(path = "/v1/gold/goals/{id}", method = [RequestMethod.GET],
            operation = Operation(operationId = "getGoal", summary = "Get goal detail",
                description = "Returns a single goal with its contribution history.",
                tags = ["Gold Goals"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Goal detail")])),
        RouterOperation(path = "/v1/gold/goals/{id}", method = [RequestMethod.PATCH],
            operation = Operation(operationId = "updateGoal", summary = "Update a goal",
                description = "Edits target/installment/deadline, or pauses/resumes auto-debit.",
                tags = ["Gold Goals"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = UpdateGoalRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Goal updated")])),
        RouterOperation(path = "/v1/gold/goals/{id}/topup", method = [RequestMethod.POST],
            operation = Operation(operationId = "topupGoal", summary = "Manual top-up",
                description = "Buys gold immediately for the given amount, tagged to this goal.",
                tags = ["Gold Goals"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = TopupGoalRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "201", description = "Top-up applied")])),
        RouterOperation(path = "/v1/gold/goals/{id}", method = [RequestMethod.DELETE],
            operation = Operation(operationId = "deleteGoal", summary = "Cancel a goal",
                description = "Deletes a goal and its contribution history.",
                tags = ["Gold Goals"],
                responses = [SwaggerApiResponse(responseCode = "204", description = "Goal deleted")]))
    )
    fun goalRoutes() = coRouter {
        "/v1/gold/goals".nest {
            POST("") { handleCreateGoal(it) }
            GET("") { handleListGoals(it) }
            GET("/{id}") { handleGetGoal(it) }
            PATCH("/{id}") { handleUpdateGoal(it) }
            POST("/{id}/topup") { handleTopup(it) }
            DELETE("/{id}") { handleDeleteGoal(it) }
        }
        // Called by Google Cloud Scheduler only -- not a user endpoint.
        // Auth is the X-Internal-Secret header check below, not JWT (see
        // FirebaseAuthFilter's skipPaths for the matching skip entry).
        POST("/v1/internal/gold-sip/run-due-debits") { handleRunDueDebits(it) }
    }

    private suspend fun handleRunDueDebits(request: ServerRequest): ServerResponse {
        val provided = request.headers().firstHeader("X-Internal-Secret")?.trim()
        val expected = internalSecret.trim()
        // Secret Manager values piped via PowerShell's `|` can pick up a
        // trailing newline that the Cloud Scheduler header value (built
        // from the same shell variable directly) doesn't have -- trim
        // both sides so that whitespace difference never causes a false
        // mismatch (confirmed as the actual cause of a 401 here, Sep 4).
        if (expected.isBlank() || provided != expected) {
            return ServerResponse.status(401).contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.error("UNAUTHORIZED", "Invalid internal secret"))
        }
        goalService.runDueGoalDebits()
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(mapOf("status" to "triggered")))
    }

    private suspend fun handleCreateGoal(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitValidatedBody<CreateGoalRequest>()
        val goal = goalService.createGoal(
            userId = userId,
            title = body.title,
            category = body.category,
            categoryEmoji = body.categoryEmoji,
            targetAmount = body.targetAmount,
            deadline = body.deadline,
            frequency = body.frequency,
            installmentAmount = body.installmentAmount
        )
        return ServerResponse.status(201).contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.created(goal))
    }

    private suspend fun handleListGoals(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val goals = goalService.listGoals(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(goals))
    }

    private suspend fun handleGetGoal(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val goalId = UUID.fromString(request.pathVariable("id"))
        val goal = goalService.getGoal(userId, goalId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(goal))
    }

    private suspend fun handleUpdateGoal(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val goalId = UUID.fromString(request.pathVariable("id"))
        val body = request.awaitValidatedBody<UpdateGoalRequest>()
        val goal = goalService.updateGoal(
            userId = userId, goalId = goalId,
            targetAmount = body.targetAmount, installmentAmount = body.installmentAmount,
            deadline = body.deadline, autoDebitActive = body.autoDebitActive
        )
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(goal))
    }

    private suspend fun handleTopup(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val goalId = UUID.fromString(request.pathVariable("id"))
        val body = request.awaitValidatedBody<TopupGoalRequest>()
        val goal = goalService.topup(userId, goalId, body.amount, body.idempotencyKey)
        return ServerResponse.status(201).contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.created(goal))
    }

    private suspend fun handleDeleteGoal(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val goalId = UUID.fromString(request.pathVariable("id"))
        goalService.deleteGoal(userId, goalId)
        return ServerResponse.noContent().buildAndAwait()
    }
}