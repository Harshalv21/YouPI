package `in`.youpi.security

import `in`.youpi.core.UnauthorizedException
import io.jsonwebtoken.Jwts
import io.jsonwebtoken.security.Keys
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.security.KeyFactory
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.time.Duration
import java.time.Instant
import java.util.*

/**
 * Issues and verifies short-lived (15min) JWTs after MPIN verification.
 * Signed with RS256 using a dedicated key pair (separate from Firebase).
 * Private key injected from GCP Secret Manager via @Value.
 */
@Service
class MpinJwtService(
    @Value("\${youpi.jwt.private-key:}") private val privateKeyBase64: String,
    @Value("\${youpi.jwt.public-key:}") private val publicKeyBase64: String,
    @Value("\${youpi.jwt.access-token-ttl:15m}") private val accessTokenTtl: Duration
) {

    private val log = LoggerFactory.getLogger(javaClass)

    private val keyPair: java.security.KeyPair by lazy {
        val generator = java.security.KeyPairGenerator.getInstance("RSA")
        generator.initialize(2048)
        generator.generateKeyPair()
    }

    private fun cleanPem(pem: String): String {
        return pem
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace("-----BEGIN PUBLIC KEY-----", "")
            .replace("-----END PUBLIC KEY-----", "")
            .replace("\\s+".toRegex(), "")
    }

    private val privateKey: PrivateKey by lazy {
        if (privateKeyBase64.isBlank()) {
            log.warn("JWT private key not configured, using ephemeral generated key")
            keyPair.private
        } else {
            val keyBytes = Base64.getDecoder().decode(cleanPem(privateKeyBase64))
            KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(keyBytes))
        }
    }

    private val publicKey: PublicKey by lazy {
        if (publicKeyBase64.isBlank()) {
            log.warn("JWT public key not configured, using ephemeral generated key")
            keyPair.public
        } else {
            val keyBytes = Base64.getDecoder().decode(cleanPem(publicKeyBase64))
            KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(keyBytes))
        }
    }

    /**
     * Issue a short-lived MPIN session JWT.
     */
    fun issueToken(userId: UUID, mobile: String, userType: String): String {
        val key = privateKey
        val now = Instant.now()

        return Jwts.builder()
            .subject(userId.toString())
            .claim("mobile", mobile)
            .claim("userType", userType)
            .claim("scope", "MPIN_SESSION")
            .issuedAt(Date.from(now))
            .expiration(Date.from(now.plus(accessTokenTtl)))
            .issuer("youpi-api")
            .signWith(key, Jwts.SIG.RS256)
            .compact()
    }

    /**
     * Verify and parse MPIN JWT. Returns claims or throws UnauthorizedException.
     */
    fun verifyToken(token: String): MpinJwtClaims {
        val key = publicKey

        try {
            val claims = Jwts.parser()
                .verifyWith(key)
                .requireIssuer("youpi-api")
                .build()
                .parseSignedClaims(token)
                .payload

            return MpinJwtClaims(
                userId = UUID.fromString(claims.subject),
                mobile = claims["mobile"] as String,
                userType = claims["userType"] as String,
                scope = claims["scope"] as String,
                expiresAt = claims.expiration.toInstant()
            )
        } catch (e: Exception) {
            log.warn("MPIN JWT verification failed: {}", e.message)
            throw UnauthorizedException("Invalid or expired MPIN session token")
        }
    }
}

data class MpinJwtClaims(
    val userId: UUID,
    val mobile: String,
    val userType: String,
    val scope: String,
    val expiresAt: Instant
)
