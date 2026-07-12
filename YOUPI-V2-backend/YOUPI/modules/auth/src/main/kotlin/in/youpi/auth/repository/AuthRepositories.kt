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
// Implements Persistable<UUID> deliberately: userId is a client-assigned
// (not DB-generated) primary key, so Spring Data R2DBC's default isNew()
// heuristic can't tell "freshly constructed, needs INSERT" apart from
// "loaded from DB, needs UPDATE" -- without this, EVERY .save() call
// (including the attempts-reset after a correct MPIN in verifyMpin())
// was attempted as an INSERT, throwing DuplicateKeyException on any row
// that already existed.
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

    // Deliberately NOT using .save() for writes to this table. userId is a
    // client-assigned (not DB-generated) primary key, so Spring Data R2DBC
    // can't reliably infer INSERT-vs-UPDATE from the entity alone --
    // Persistable<UUID> with a @Transient "isNew" constructor flag was tried
    // and fails with "No property isNewRecord found ... to bind constructor
    // parameter to" (Spring Data's constructor-based instantiator requires
    // every primary-constructor parameter to resolve to a known persistent
    // property, which @Transient explicitly excludes it from). A native
    // Postgres UPSERT sidesteps the whole problem -- it's correct whether or
    // not the row already exists, with no ambiguity for Spring to get wrong.
    @Query("""
        INSERT INTO user_mpin (user_id, mpin_hash, attempts, locked_until, updated_at)
        VALUES (:userId, :mpinHash, :attempts, :lockedUntil, :updatedAt)
        ON CONFLICT (user_id) DO UPDATE SET
            mpin_hash = EXCLUDED.mpin_hash,
            attempts = EXCLUDED.attempts,
            locked_until = EXCLUDED.locked_until,
            updated_at = EXCLUDED.updated_at
    """)
    suspend fun upsert(
        userId: UUID,
        mpinHash: String,
        attempts: Int,
        lockedUntil: Instant?,
        updatedAt: Instant
    )
}

// ── User Trusted Device Entity ──
// Backs MPIN-only login's device-binding check. A row here means this
// device_id has already proven phone-number possession via OTP/Firebase
// verification for this user, so it's allowed to use MPIN-only login
// without repeating OTP. See AuthService.verifyMpin / trustDevice().
@Table("user_trusted_devices")
data class UserTrustedDeviceEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val deviceId: String,
    val firstTrustedAt: Instant = Instant.now(),
    val lastUsedAt: Instant = Instant.now()
)

interface UserTrustedDeviceRepository : CoroutineCrudRepository<UserTrustedDeviceEntity, UUID> {
    suspend fun findByUserIdAndDeviceId(userId: UUID, deviceId: String): UserTrustedDeviceEntity?

    @Query("UPDATE user_trusted_devices SET last_used_at = NOW() WHERE user_id = :userId AND device_id = :deviceId")
    suspend fun touch(userId: UUID, deviceId: String)
}