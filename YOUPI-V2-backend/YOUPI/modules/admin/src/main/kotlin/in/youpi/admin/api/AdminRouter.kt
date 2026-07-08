package `in`.youpi.admin.api

import `in`.youpi.admin.service.AdminService
import `in`.youpi.core.ApiResponse
import `in`.youpi.security.currentUserId
import `in`.youpi.security.requireAdmin
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.responses.ApiResponse as SwaggerApiResponse
import org.springdoc.core.annotations.RouterOperation
import org.springdoc.core.annotations.RouterOperations
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.RequestMethod
import org.springframework.web.reactive.function.server.*

@Configuration
class AdminRouter(private val adminService: AdminService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/admin/dashboard", method = [RequestMethod.GET],
            operation = Operation(operationId = "getDashboard", summary = "Admin dashboard",
                description = "Returns dashboard statistics: total users, KYC count, recharge count, etc. Admin only.",
                tags = ["Admin"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Dashboard statistics")])),
        RouterOperation(path = "/v1/admin/users", method = [RequestMethod.GET],
            operation = Operation(operationId = "listUsers", summary = "List all users",
                description = "Returns a paginated list of all users. Admin only.",
                tags = ["Admin"],
                parameters = [Parameter(name = "page", description = "Page number (0-based)", required = false)],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Paginated user list")])),
        RouterOperation(path = "/v1/admin/users/{userId}", method = [RequestMethod.GET],
            operation = Operation(operationId = "getUserDetails", summary = "Get user details",
                description = "Returns detailed information for a specific user. Admin only.",
                tags = ["Admin"],
                parameters = [Parameter(name = "userId", description = "UUID of the user", required = true)],
                responses = [SwaggerApiResponse(responseCode = "200", description = "User details")])),
        RouterOperation(path = "/v1/admin/users/{userId}/type", method = [RequestMethod.PUT],
            operation = Operation(operationId = "updateUserType", summary = "Update user type",
                description = "Changes a user's type (NORMAL, SMART_SAVER, ADMIN). Admin only.",
                tags = ["Admin"],
                parameters = [Parameter(name = "userId", description = "UUID of the user", required = true)],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Updated user")])),
        RouterOperation(path = "/v1/admin/users/{userId}/active", method = [RequestMethod.PUT],
            operation = Operation(operationId = "toggleUserActive", summary = "Toggle user active status",
                description = "Activates or deactivates a user account. Admin only.",
                tags = ["Admin"],
                parameters = [Parameter(name = "userId", description = "UUID of the user", required = true)],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Updated user status")]))
    )
    fun adminRoutes() = coRouter {
        "/v1/admin".nest {
            GET("/dashboard") { handleDashboard(it) }
            GET("/users") { handleListUsers(it) }
            GET("/users/{userId}") { handleUserDetails(it) }
            PUT("/users/{userId}/type") { handleUpdateUserType(it) }
            PUT("/users/{userId}/active") { handleToggleActive(it) }
        }
    }

    private suspend fun handleDashboard(request: ServerRequest): ServerResponse {
        request.requireAdmin()
        val dashboard = adminService.getDashboard()
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(dashboard))
    }

    private suspend fun handleListUsers(request: ServerRequest): ServerResponse {
        request.requireAdmin()
        val page = request.queryParam("page").map { it.toInt() }.orElse(0)
        val users = adminService.listUsers(page)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(users))
    }

    private suspend fun handleUserDetails(request: ServerRequest): ServerResponse {
        request.requireAdmin()
        val userId = java.util.UUID.fromString(request.pathVariable("userId"))
        val user = adminService.getUserDetails(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(user))
    }

    private suspend fun handleUpdateUserType(request: ServerRequest): ServerResponse {
        request.requireAdmin()
        val userId = java.util.UUID.fromString(request.pathVariable("userId"))
        val body = request.awaitBody<Map<String, String>>()
        val userType = body["userType"] ?: throw IllegalArgumentException("userType required")
        val user = adminService.updateUserType(userId, userType)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(user))
    }

    private suspend fun handleToggleActive(request: ServerRequest): ServerResponse {
        request.requireAdmin()
        val userId = java.util.UUID.fromString(request.pathVariable("userId"))
        val body = request.awaitBody<Map<String, Boolean>>()
        val isActive = body["isActive"] ?: throw IllegalArgumentException("isActive required")
        val user = adminService.toggleUserActive(userId, isActive)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(user))
    }
}
