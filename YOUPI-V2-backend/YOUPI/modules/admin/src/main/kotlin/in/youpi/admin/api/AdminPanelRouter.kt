package `in`.youpi.admin.api

import `in`.youpi.admin.domain.*
import `in`.youpi.admin.service.AdminAuthService
import `in`.youpi.admin.service.AdminJwtService
import `in`.youpi.admin.service.AdminPanelService
import `in`.youpi.core.ApiResponse
import `in`.youpi.core.NotFoundException
import `in`.youpi.core.Result
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.web.reactive.function.server.*
import java.util.UUID

/**
 * DELIBERATELY separate from the existing AdminRouter.kt -- different
 * @Bean name (adminPanelRoutes vs adminRoutes), different URL prefix
 * (/v1/admin-panel vs /v1/admin), different auth mechanism (own JWT via
 * requireAdmin() below, NOT the security package's requireAdmin() which
 * reads Firebase-auth exchange attributes). This avoids any path/bean
 * collision with the existing admin router and keeps the two admin
 * surfaces (in-app admin actions vs standalone web panel) fully
 * independent, as agreed in the design discussion.
 */
@Configuration
class AdminPanelRouter(
    private val adminAuthService: AdminAuthService,
    private val adminPanelService: AdminPanelService,
    private val adminJwtService: AdminJwtService
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Bean
    fun adminPanelRoutes() = coRouter {
        "/v1/admin-panel".nest {
            POST("/auth/login") { handleLogin(it) }
            GET("/dashboard/stats") { handleDashboardStats(it) }
            GET("/users") { handleGetUsers(it) }
            "/users/{id}".nest {
                PATCH("/status") { handleUpdateUserStatus(it) }
            }
            GET("/transactions") { handleGetTransactions(it) }
            GET("/gold-ledger") { handleGetGoldLedger(it) }
        }
    }

    private suspend fun requireAdmin(request: ServerRequest): UUID? {
        val header = request.headers().firstHeader("Authorization") ?: return null
        if (!header.startsWith("Bearer ")) return null
        val token = header.removePrefix("Bearer ").trim()
        val claims = adminJwtService.verify(token) ?: return null
        return try { UUID.fromString(claims.subject) } catch (e: Exception) { null }
    }

    private suspend fun unauthorized(): ServerResponse =
        ServerResponse.status(HttpStatus.UNAUTHORIZED).contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(mapOf("success" to false, "error" to mapOf(
                "code" to "ADMIN_UNAUTHORIZED", "message" to "Admin authentication required."
            )))

    private suspend fun handleLogin(request: ServerRequest): ServerResponse {
        val body = request.awaitBody<AdminLoginRequest>()
        return when (val result = adminAuthService.login(body)) {
            is Result.Success -> ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(result.value))
            is Result.Failure -> throw result.error
        }
    }

    private suspend fun handleDashboardStats(request: ServerRequest): ServerResponse {
        requireAdmin(request) ?: return unauthorized()
        val stats = adminPanelService.getDashboardStats()
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(stats))
    }

    private suspend fun handleGetUsers(request: ServerRequest): ServerResponse {
        requireAdmin(request) ?: return unauthorized()
        val search = request.queryParam("search").orElse("")
        val kyc = request.queryParam("kyc").orElse("ALL")
        val page = request.queryParam("page").orElse("0").toIntOrNull() ?: 0
        val pageSize = request.queryParam("pageSize").orElse("20").toIntOrNull()?.coerceIn(1, 100) ?: 20
        val result = adminPanelService.searchUsers(search, kyc, page, pageSize)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(result))
    }

    private suspend fun handleUpdateUserStatus(request: ServerRequest): ServerResponse {
        requireAdmin(request) ?: return unauthorized()
        val userId = UUID.fromString(request.pathVariable("id"))
        val body = request.awaitBody<UpdateUserActiveRequest>()
        return try {
            adminPanelService.toggleUserActive(userId, body.isActive)
            ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(ApiResponse.ok(mapOf("isActive" to body.isActive)))
        } catch (e: NotFoundException) {
            ServerResponse.status(HttpStatus.NOT_FOUND).contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(mapOf("success" to false, "error" to mapOf(
                    "code" to "ADMIN_USER_NOT_FOUND", "message" to "User $userId not found."
                )))
        }
    }

    private suspend fun handleGetTransactions(request: ServerRequest): ServerResponse {
        requireAdmin(request) ?: return unauthorized()
        val search = request.queryParam("search").orElse("")
        val status = request.queryParam("status").orElse("ALL")
        val page = request.queryParam("page").orElse("0").toIntOrNull() ?: 0
        val pageSize = request.queryParam("pageSize").orElse("20").toIntOrNull()?.coerceIn(1, 100) ?: 20
        val result = adminPanelService.getTransactions(search, status, page, pageSize)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(result))
    }

    private suspend fun handleGetGoldLedger(request: ServerRequest): ServerResponse {
        requireAdmin(request) ?: return unauthorized()
        val search = request.queryParam("search").orElse("")
        val page = request.queryParam("page").orElse("0").toIntOrNull() ?: 0
        val pageSize = request.queryParam("pageSize").orElse("20").toIntOrNull()?.coerceIn(1, 100) ?: 20
        val result = adminPanelService.getGoldLedger(search, page, pageSize)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(result))
    }
}