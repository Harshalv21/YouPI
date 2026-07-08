package `in`.youpi.security

import `in`.youpi.core.ForbiddenException
import `in`.youpi.core.UnauthorizedException
import org.springframework.web.reactive.function.server.ServerRequest
import org.springframework.web.server.ServerWebExchange
import java.util.UUID

/**
 * Extension functions for extracting auth context from requests.
 * Used throughout all service and router layers.
 */

/** Extract the current authenticated user's ID */
fun ServerWebExchange.currentUserId(): UUID {
    val principal = attributes["firebase.principal"] as? FirebasePrincipal
        ?: throw UnauthorizedException("No authenticated user in context")
    // userId is stored in exchange attributes by AuthService after OTP/MPIN verification
    val userId = attributes["auth.userId"] as? UUID
        ?: throw UnauthorizedException("User ID not resolved")
    return userId
}

/** Extract the full FirebasePrincipal */
fun ServerWebExchange.currentPrincipal(): FirebasePrincipal {
    return attributes["firebase.principal"] as? FirebasePrincipal
        ?: throw UnauthorizedException("No authenticated user in context")
}

/** Extract userId from ServerRequest (wraps exchange) */
fun ServerRequest.currentUserId(): UUID {
    val userId = this.exchange().attributes["auth.userId"] as? UUID
    if (userId != null) return userId
    val principal = this.exchange().attributes["firebase.principal"] as? FirebasePrincipal
        ?: throw UnauthorizedException("No authenticated user in context")
    // Fallback: parse from Firebase UID attribute
    return this.exchange().attributes["auth.userId"] as? UUID
        ?: throw UnauthorizedException("User ID not resolved")
}

/** Require a specific user type (NORMAL, SMART_SAVER, ADMIN) */
fun ServerRequest.requireUserType(vararg types: String) {
    val userType = this.exchange().attributes["auth.userType"] as? String ?: "NORMAL"
    if (userType !in types) {
        throw ForbiddenException("Required user type: ${types.joinToString()}, found: $userType")
    }
}

/** Convenience: require ADMIN user type */
fun ServerRequest.requireAdmin() = requireUserType("ADMIN")
