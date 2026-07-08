package `in`.youpi.security

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.reactor.mono
import kotlinx.coroutines.withContext
import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.web.server.ServerWebExchange
import org.springframework.web.server.WebFilter
import org.springframework.web.server.WebFilterChain
import reactor.core.publisher.Mono

/**
 * WebFlux filter that verifies Firebase Auth Bearer tokens.
 * On success: injects FirebasePrincipal into exchange attributes.
 * On failure: returns 401 with ApiResponse error.
 * Skips: public auth endpoints, webhooks, and actuator health.
 */
@Component
class FirebaseAuthFilter(
    private val mpinJwtService: MpinJwtService
) : WebFilter {

    private val log = LoggerFactory.getLogger(javaClass)

    private val skipPaths = listOf(
        "/api/v1/auth/otp/",
        "/api/v1/auth/firebase/verify",
        "/api/v1/auth/mpin/verify",
        "/api/v1/auth/token/refresh",
        "/api/v1/gold/price",
        "/webhooks/",
        "/actuator/",
	    "/api/actuator/",
        "/swagger-ui",
        "/swagger-ui.html",
        "/v3/api-docs",
        "/webjars/",
        "/api/swagger-ui",
        "/api/swagger-ui.html",
        "/api/v3/api-docs",
        "/api/webjars/"
    )

    override fun filter(exchange: ServerWebExchange, chain: WebFilterChain): Mono<Void> {
        val path = exchange.request.uri.path

        // Skip filter for public endpoints
        if (skipPaths.any { path.startsWith(it) }) {
            return chain.filter(exchange)
        }

        val authHeader = exchange.request.headers.getFirst("Authorization")

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return writeUnauthorized(exchange, "Missing or invalid Authorization header")
        }

        val token = authHeader.removePrefix("Bearer ").trim()

        return mono {
            try {
                // Try parsing as MPIN JWT first
                val mpinClaims = mpinJwtService.verifyToken(token)
                val principal = FirebasePrincipal(
                    uid = mpinClaims.userId.toString(),
                    mobile = mpinClaims.mobile,
                    email = null,
                    claims = mapOf("userType" to mpinClaims.userType)
                )
                exchange.attributes["firebase.principal"] = principal
                exchange.attributes["auth.userId"] = mpinClaims.userId
                exchange.attributes["auth.userType"] = mpinClaims.userType
                null // success
            } catch (jwtException: Exception) {
                // Fallback to Firebase verify
                try {
                    val firebaseToken = withContext(Dispatchers.IO) {
                        FirebaseAuth.getInstance().verifyIdToken(token)
                    }
                    val principal = FirebasePrincipal(
                        uid = firebaseToken.uid,
                        mobile = firebaseToken.claims["phone_number"] as? String,
                        email = firebaseToken.email,
                        claims = firebaseToken.claims
                    )
                    exchange.attributes["firebase.principal"] = principal
                    null // success
                } catch (e: Exception) {
                    log.warn("Both MPIN JWT and Firebase token verification failed: {}", e.message)
                    "TOKEN_INVALID"
                }
            }
        }.flatMap { error ->
            if (error != null) {
                writeUnauthorized(exchange, "Invalid or expired token")
            } else {
                chain.filter(exchange)
            }
        }
    }

    private fun writeUnauthorized(exchange: ServerWebExchange, message: String): Mono<Void> {
        exchange.response.statusCode = HttpStatus.UNAUTHORIZED
        exchange.response.headers.set("Content-Type", "application/json")
        val body = """{"success":false,"error":{"code":"UNAUTHORIZED","message":"$message"}}"""
        val buffer = exchange.response.bufferFactory().wrap(body.toByteArray())
        return exchange.response.writeWith(Mono.just(buffer))
    }
}

/**
 * Principal extracted from a verified Firebase token.
 */
data class FirebasePrincipal(
    val uid: String,
    val mobile: String?,
    val email: String?,
    val claims: Map<String, Any> = emptyMap()
)
