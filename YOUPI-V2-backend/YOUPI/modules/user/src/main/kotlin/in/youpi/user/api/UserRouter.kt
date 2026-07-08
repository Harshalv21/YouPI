package `in`.youpi.user.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.Result
import `in`.youpi.security.currentUserId
import `in`.youpi.user.domain.*
import `in`.youpi.user.service.UserService
import io.swagger.v3.oas.annotations.Operation
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

@Configuration
@Tag(name = "User")
class UserRouter(private val userService: UserService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/user/profile", method = [RequestMethod.GET],
            operation = Operation(operationId = "getProfile", summary = "Get user profile",
                description = "Fetches the authenticated user's profile data.",
                tags = ["User"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "User profile")])),
        RouterOperation(path = "/v1/user/profile", method = [RequestMethod.PUT],
            operation = Operation(operationId = "updateProfile", summary = "Update user profile",
                description = "Updates the user's name, email, date of birth.",
                tags = ["User"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = UpdateProfileRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Updated profile")])),
        RouterOperation(path = "/v1/user/kyc/status", method = [RequestMethod.GET],
            operation = Operation(operationId = "getKycStatus", summary = "Get KYC status",
                description = "Returns the current KYC verification status and step.",
                tags = ["User"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "KYC status")])),
        RouterOperation(path = "/v1/user/kyc/aadhaar/otp", method = [RequestMethod.POST],
            operation = Operation(operationId = "initiateAadhaarOtp", summary = "Initiate Aadhaar OTP",
                description = "Sends an OTP to the Aadhaar-linked mobile for e-KYC.",
                tags = ["User"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = AadhaarOtpRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Aadhaar OTP sent")])),
        RouterOperation(path = "/v1/user/kyc/aadhaar/verify", method = [RequestMethod.POST],
            operation = Operation(operationId = "verifyAadhaar", summary = "Verify Aadhaar OTP",
                description = "Verifies the Aadhaar OTP and moves KYC to AADHAAR_DONE.",
                tags = ["User"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = AadhaarVerifyRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Aadhaar verified")])),
        RouterOperation(path = "/v1/user/kyc/pan/verify", method = [RequestMethod.POST],
            operation = Operation(operationId = "verifyPan", summary = "Verify PAN card",
                description = "Verifies the PAN number via Karza API, moves KYC to PAN_DONE.",
                tags = ["User"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = PanVerifyRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "PAN verified")])),
        RouterOperation(path = "/v1/user/kyc/selfie", method = [RequestMethod.POST],
            operation = Operation(operationId = "uploadSelfie", summary = "Upload selfie for face match",
                description = "Uploads a selfie (base64) for face-match verification against Aadhaar photo.",
                tags = ["User"],
                requestBody = SwaggerRequestBody(content = [Content(schema = Schema(implementation = SelfieUploadRequest::class))]),
                responses = [SwaggerApiResponse(responseCode = "200", description = "Selfie verified")]))
    )
    fun userRoutes() = coRouter {
        "/v1/user".nest {
            GET("/profile") { handleGetProfile(it) }
            PUT("/profile") { handleUpdateProfile(it) }
            GET("/kyc/status") { handleKycStatus(it) }
            POST("/kyc/aadhaar/otp") { handleAadhaarOtp(it) }
            POST("/kyc/aadhaar/verify") { handleAadhaarVerify(it) }
            POST("/kyc/pan/verify") { handlePanVerify(it) }
            POST("/kyc/selfie") { handleSelfieUpload(it) }
        }
    }

    private suspend fun handleGetProfile(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val profile = userService.getProfile(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(profile))
    }

    private suspend fun handleUpdateProfile(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<UpdateProfileRequest>()
        val profile = userService.updateProfile(userId, body)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(profile))
    }

    private suspend fun handleKycStatus(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val status = userService.getKycStatus(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(status))
    }

    private suspend fun handleAadhaarOtp(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<AadhaarOtpRequest>()
        return when (val result = userService.initiateAadhaarOtp(userId, body.aadhaarNumber)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleAadhaarVerify(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<AadhaarVerifyRequest>()
        return when (val result = userService.verifyAadhaarOtp(userId, body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handlePanVerify(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<PanVerifyRequest>()
        return when (val result = userService.verifyPan(userId, body.panNumber)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleSelfieUpload(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<SelfieUploadRequest>()
        return when (val result = userService.uploadSelfie(userId, body.selfieBase64)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }
}
