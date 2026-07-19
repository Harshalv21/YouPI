package `in`.youpi.security

import `in`.youpi.core.UnauthorizedException
import io.jsonwebtoken.Jwts
import io.jsonwebtoken.security.Keys
import jakarta.annotation.PostConstruct
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
    @Value("\${youpi.jwt.access-token-ttl:15m}") private val accessTokenTtl: Duration,
    @Value("\${spring.profiles.active:}") private val activeProfiles: String
) {

    private val log = LoggerFactory.getLogger(javaClass)

    @PostConstruct
    fun validateKeysAtStartup() {
        // Touch the lazy delegates now so a missing/misconfigured key fails
        // the deploy immediately, instead of surfacing only on the first
        // login/token-verify request in production.
        privateKey
        publicKey
        log.info("MpinJwtService: signing keys initialized (profiles='$activeProfiles')")
    }

    // Ephemeral keys are ONLY acceptable for local/dev work where no secret
    // is configured. In gcp/prod, a missing key must fail startup loudly --
    // silently falling back here would mean every restart mints a fresh
    // keypair and invalidates every previously-issued session token without
    // anyone noticing, and worse, would let the service "look healthy" while
    // running on a non-persisted, non-audited signing key.
    private val isProdLikeProfile: Boolean
        get() = activeProfiles.split(",").map { it.trim() }.any { it == "gcp" || it == "prod" || it == "production" }

    private val keyPair: java.security.KeyPair by lazy {
        check(!isProdLikeProfile) {
            "FATAL: youpi.jwt.private-key/public-key not configured in profile(s) '$activeProfiles'. " +
                    "Refusing to start with an ephemeral JWT signing key in a production-like environment."
        }
        log.warn("JWT keys not configured, generating ephemeral key pair (dev/local only)")
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
            keyPair.private
        } else {
            val keyBytes = Base64.getDecoder().decode(cleanPem(privateKeyBase64))
            KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(keyBytes))
        }
    }

    private val publicKey: PublicKey by lazy {
        if (publicKeyBase64.isBlank()) {
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