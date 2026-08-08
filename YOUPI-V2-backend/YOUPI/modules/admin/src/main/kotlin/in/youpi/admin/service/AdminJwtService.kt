package `in`.youpi.admin.service

import io.jsonwebtoken.Claims
import io.jsonwebtoken.Jwts
import io.jsonwebtoken.security.Keys
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.util.Date
import java.util.UUID
import javax.crypto.SecretKey

/**
 * Deliberately SEPARATE from MpinJwtService (the regular user-session JWT
 * system) -- admin tokens and user tokens must never be interchangeable.
 * Uses a dedicated secret (ADMIN_JWT_SECRET) and its own issuer claim so
 * AdminPanelRouter can reject a foreign/user token outright.
 *
 * Written against jjwt 0.12.5 (this project's pinned version) -- NOTE this
 * API is meaningfully different from jjwt 0.11.x:
 *   .setIssuer()/.setSubject()/.setIssuedAt()/.setExpiration() -> .issuer()/.subject()/.issuedAt()/.expiration()
 *   .signWith(key, SignatureAlgorithm.HS256) -> .signWith(key)  (algorithm now inferred from key type)
 *   Jwts.parserBuilder() -> Jwts.parser()
 *   .setSigningKey(key) -> .verifyWith(key)
 *   .parseClaimsJws(token) -> .parseSignedClaims(token)
 *   .body -> .payload
 * If this project's jjwt version ever changes, re-check this file against
 * the jjwt migration guide for that version.
 */
@Service
class AdminJwtService(
    @Value("\${youpi.admin.jwt-secret:}") private val secretRaw: String
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private val key: SecretKey by lazy {
        require(secretRaw.length >= 32) {
            "youpi.admin.jwt-secret must be at least 32 characters"
        }
        Keys.hmacShaKeyFor(secretRaw.toByteArray())
    }

    companion object {
        private const val ISSUER = "youpi-admin"
        private val TTL_MILLIS = 8 * 60 * 60 * 1000L // 8 hours
    }

    fun issueToken(adminId: UUID, email: String, role: String): String {
        val now = Date()
        return Jwts.builder()
            .issuer(ISSUER)
            .subject(adminId.toString())
            .claim("email", email)
            .claim("role", role)
            .issuedAt(now)
            .expiration(Date(now.time + TTL_MILLIS))
            .signWith(key)
            .compact()
    }

    /** Returns claims if valid, null if expired/malformed/wrong issuer -- never throws. */
    fun verify(token: String): Claims? {
        return try {
            val claims = Jwts.parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .payload
            if (claims.issuer != ISSUER) {
                log.warn("Admin JWT rejected: wrong issuer '{}'", claims.issuer)
                return null
            }
            claims
        } catch (e: Exception) {
            log.warn("Admin JWT verification failed: {}", e.message)
            null
        }
    }
}