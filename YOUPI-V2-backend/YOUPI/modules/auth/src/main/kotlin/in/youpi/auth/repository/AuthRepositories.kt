package `in`.youpi.auth.repository

import org.springframework.data.annotation.Id
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.data.r2dbc.repository.Query
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

// ── User Entity ──
@Table("users")
data class UserEntity(
    @Id val id: UUID? = null,
    val mobile: String,
    val fullName: String? = null,
    val email: String? = null,
    val dateOfBirth: LocalDate? = null,
    val firebaseUid: String? = null,
    val isActive: Boolean = true,
    val isKycVerified: Boolean = false,
    val userType: String = "NORMAL",
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
)

interface UserRepository : CoroutineCrudRepository<UserEntity, UUID> {
    suspend fun findByMobile(mobile: String): UserEntity?
    suspend fun findByFirebaseUid(firebaseUid: String): UserEntity?
    suspend fun existsByMobile(mobile: String): Boolean
}

// ── OTP Session Entity ──
@Table("otp_sessions")
data class OtpSessionEntity(
    @Id val id: UUID? = null,
    val mobile: String,
    val otpHash: String,
    val purpose: String,
    val attempts: Int = 0,
    val maxAttempts: Int = 3,
    val expiresAt: Instant,
    val verified: Boolean = false,
    val createdAt: Instant = Instant.now()
)

interface OtpSessionRepository : CoroutineCrudRepository<OtpSessionEntity, UUID> {
    @Query("SELECT * FROM otp_sessions WHERE mobile = :mobile AND purpose = :purpose ORDER BY created_at DESC LIMIT 1")
    suspend fun findLatest(mobile: String, purpose: String): OtpSessionEntity?
}

// ── Refresh Token Entity ──
@Table("refresh_tokens")
data class RefreshTokenEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val tokenHash: String,
    val deviceId: String? = null,
    val deviceName: String? = null,
    val expiresAt: Instant,
    val revoked: Boolean = false,
    val revokedAt: Instant? = null,
    val createdAt: Instant = Instant.now()
)

interface RefreshTokenRepository : CoroutineCrudRepository<RefreshTokenEntity, UUID> {
    suspend fun findByTokenHashAndRevokedFalse(tokenHash: String): RefreshTokenEntity?

    @Query("UPDATE refresh_tokens SET revoked = true, revoked_at = NOW() WHERE user_id = :userId AND revoked = false")
    suspend fun revokeAllByUserId(userId: UUID)

    @Query("UPDATE refresh_tokens SET revoked = true, revoked_at = NOW() WHERE id = :id")
    suspend fun revokeById(id: UUID)
}

// ── User MPIN Entity ──
@Table("user_mpin")
data class UserMpinEntity(
    val userId: UUID,
    val mpinHash: String,
    val attempts: Int = 0,
    val lockedUntil: Instant? = null,
    val updatedAt: Instant = Instant.now()
) {
    @Id
    fun getId(): UUID = userId
}

interface UserMpinRepository : CoroutineCrudRepository<UserMpinEntity, UUID> {
    suspend fun findByUserId(userId: UUID): UserMpinEntity?
}
