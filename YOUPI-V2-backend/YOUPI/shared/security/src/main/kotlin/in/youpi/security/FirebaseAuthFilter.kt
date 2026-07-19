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
        "/api/webhooks/",
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
        val normalizedPath = path.replace(Regex("/+"), "/")
        val method = exchange.request.method

        if (method?.name() == "OPTIONS") {
            return chain.filter(exchange)
        }

        if (skipPaths.any { normalizedPath.startsWith(it) }) {
            return chain.filter(exchange)
        }

        val authHeader = exchange.request.headers.getFirst("Authorization")

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return writeUnauthorized(exchange, "Missing or invalid Authorization header")
        }

        // Never log the raw token or Authorization header value anywhere below
        // this point -- it's a live bearer credential, and log entries are
        // readable by anyone with log-viewer IAM, not just admins.
        val token = authHeader.removePrefix("Bearer ").trim()

        return mono {
            try {
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
                ""
            } catch (jwtException: Exception) {
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
                    ""
                } catch (e: Exception) {
                    log.warn("Token verification failed for {} {}: {}", method, normalizedPath, e.message)
                    "TOKEN_INVALID"
                }
            }
        }.flatMap { error ->
            if (error == "TOKEN_INVALID") {
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

data class FirebasePrincipal(
    val uid: String,
    val mobile: String?,
    val email: String?,
    val claims: Map<String, Any> = emptyMap()
)