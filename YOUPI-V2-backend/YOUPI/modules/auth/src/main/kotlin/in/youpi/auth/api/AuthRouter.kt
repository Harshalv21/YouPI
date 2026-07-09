package `in`.youpi.auth.api

import `in`.youpi.auth.domain.*
import `in`.youpi.auth.service.AuthService
import org.slf4j.LoggerFactory
import `in`.youpi.core.ApiResponse
import `in`.youpi.security.currentUserId
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.media.Content
import io.swagger.v3.oas.annotations.media.Schema
import io.swagger.v3.oas.annotations.parameters.RequestBody as SwaggerRequestBody
import io.swagger.v3.oas.annotations.responses.ApiResponse as SwaggerApiResponse
import io.swagger.v3.oas.annotations.tags.Tag
import org.springdoc.core.annotations.RouterOperation
import org.springdoc.core.annotations.RouterOperations
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.RequestMethod
import org.springframework.web.reactive.function.server.*
import org.springframework.web.reactive.function.server.ServerResponse.ok

/**
 * Auth API router — WebFlux functional routing with OpenAPI annotations.
 */
@Configuration
@Tag(name = "Auth")
class AuthRouter(private val authService: AuthService) {
    private val logger = LoggerFactory.getLogger(AuthRouter::class.java)

    init {
        logger.info("AuthRouter initialized - Registering /api/v1/auth routes")
    }

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/auth/otp/send", method = [RequestMethod.POST],
            operation = Operation(operationId = "sendOtp", summary = "Send OTP to mobile",
                description = "Sends a 6-digit OTP to the given mobile number for login/registration.",
                tags = ["Auth"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = SendOtpRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "OTP sent successfully")])),
        RouterOperation(path = "/v1/auth/otp/verify", method = [RequestMethod.POST],
            operation = Operation(operationId = "verifyOtp", summary = "Verify OTP",
                description = "Verifies the OTP and returns Firebase custom token + access/refresh tokens.",
                tags = ["Auth"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = VerifyOtpRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "OTP verified, tokens issued")])),
        RouterOperation(path = "/v1/auth/mpin/setup", method = [RequestMethod.POST],
            operation = Operation(operationId = "setupMpin", summary = "Setup MPIN",
                description = "Sets a 4-digit MPIN for the authenticated user. Requires Bearer token.",
                tags = ["Auth"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = MpinSetupRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "MPIN set successfully")])),
        RouterOperation(path = "/v1/auth/mpin/verify", method = [RequestMethod.POST],
            operation = Operation(operationId = "verifyMpin", summary = "Verify MPIN",
                description = "Verifies the MPIN and issues short-lived access + refresh tokens.",
                tags = ["Auth"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = MpinVerifyRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "MPIN verified, tokens issued")])),
        RouterOperation(path = "/v1/auth/token/refresh", method = [RequestMethod.POST],
            operation = Operation(operationId = "refreshToken", summary = "Refresh access token",
                description = "Uses a valid refresh token to get a new access token.",
                tags = ["Auth"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = RefreshTokenRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "New access token issued")])),
        RouterOperation(path = "/v1/auth/logout", method = [RequestMethod.POST],
            operation = Operation(operationId = "logout", summary = "Logout",
                description = "Revokes the refresh token and logs out the user.",
                tags = ["Auth"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = RefreshTokenRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Logged out successfully")])),
        RouterOperation(path = "/v1/auth/firebase/verify", method = [RequestMethod.POST],
            operation = Operation(operationId = "verifyFirebaseToken", summary = "Verify Firebase ID token",
                description = "Verifies a Firebase phone-auth ID token and issues access/refresh tokens. " +
                        "This is the endpoint the Flutter app actually calls after Firebase OTP verification.",
                tags = ["Auth"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = FirebaseVerifyRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Firebase token verified, tokens issued")]))
    )
    fun authRoutes() = coRouter {
        "/v1/auth".nest {
            POST("/otp/send") { handleSendOtp(it) }
            POST("/otp/verify") { handleVerifyOtp(it) }
            POST("/mpin/setup") { handleMpinSetup(it) }
            POST("/mpin/verify") { handleMpinVerify(it) }
            POST("/token/refresh") { handleRefreshToken(it) }
            POST("/logout") { handleLogout(it) }
            POST("/firebase/verify") { handleFirebaseVerify(it) }
        }
    }

    private suspend fun handleSendOtp(request: ServerRequest): ServerResponse {
        val body = request.awaitBody<SendOtpRequest>()
        return when (val result = authService.sendOtp(body.mobile)) {
            is `in`.youpi.core.Result.Success ->
                ok().contentType(MediaType.APPLICATION_JSON)
                    .bodyValueAndAwait(ApiResponse.ok(result.value))
            is `in`.youpi.core.Result.Failure ->
                throw result.error
        }
    }
    private suspend fun handleVerifyOtp(request: ServerRequest): ServerResponse {
        val body = request.awaitBody<VerifyOtpRequest>()
        return when (val result = authService.verifyOtp(body)) {
            is `in`.youpi.core.Result.Success ->
                ok().contentType(MediaType.APPLICATION_JSON)
                    .bodyValueAndAwait(ApiResponse.ok(result.value))
            is `in`.youpi.core.Result.Failure ->
                throw result.error
        }
    }

    private suspend fun handleFirebaseVerify(request: ServerRequest): ServerResponse {
        val body = request.awaitBody<FirebaseVerifyRequest>()
        return when (val result = authService.verifyFirebaseToken(body.idToken, body.deviceId)) {
            is `in`.youpi.core.Result.Success ->
                ok().contentType(MediaType.APPLICATION_JSON)
                    .bodyValueAndAwait(ApiResponse.ok(result.value))
            is `in`.youpi.core.Result.Failure ->
                throw result.error
        }
    }

    private suspend fun handleMpinSetup(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<MpinSetupRequest>()
        authService.setupMpin(userId, body.mpin)
        return ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(mapOf("message" to "MPIN set successfully")))
    }

    private suspend fun handleMpinVerify(request: ServerRequest): ServerResponse {
        val body = request.awaitBody<MpinVerifyRequest>()
        return when (val result = authService.verifyMpin(body)) {
            is `in`.youpi.core.Result.Success ->
                ok().contentType(MediaType.APPLICATION_JSON)
                    .bodyValueAndAwait(ApiResponse.ok(result.value))
            is `in`.youpi.core.Result.Failure ->
                throw result.error
        }
    }

    private suspend fun handleRefreshToken(request: ServerRequest): ServerResponse {
        val body = request.awaitBody<RefreshTokenRequest>()
        return when (val result = authService.refreshAccessToken(body.refreshToken)) {
            is `in`.youpi.core.Result.Success ->
                ok().contentType(MediaType.APPLICATION_JSON)
                    .bodyValueAndAwait(ApiResponse.ok(result.value))
            is `in`.youpi.core.Result.Failure ->
                throw result.error
        }
    }

    private suspend fun handleLogout(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<RefreshTokenRequest>()
        authService.logout(userId, body.refreshToken)
        return ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(mapOf("message" to "Logged out successfully")))
    }
}