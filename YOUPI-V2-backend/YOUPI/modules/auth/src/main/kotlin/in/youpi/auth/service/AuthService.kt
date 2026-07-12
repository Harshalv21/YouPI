package `in`.youpi.auth.service

import `in`.youpi.auth.domain.*
import `in`.youpi.auth.repository.*
import `in`.youpi.events.PubSubPublisher
import `in`.youpi.core.Result
import `in`.youpi.security.MpinJwtService
import `in`.youpi.security.OtpService
import at.favre.lib.crypto.bcrypt.BCrypt
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Duration
import java.time.Instant
import java.util.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Core authentication service — OTP login, MPIN setup/verify, refresh tokens.
 *
 * All functions are suspend (coroutine-native).
 * NEVER throws raw Exception — always returns Result or throws sealed AuthException.
 */
@Service
class AuthService(
    private val userRepo: UserRepository,
    private val otpSessionRepo: OtpSessionRepository,
    private val refreshTokenRepo: RefreshTokenRepository,
    private val mpinRepo: UserMpinRepository,
    private val trustedDeviceRepo: UserTrustedDeviceRepository,
    private val pubSubPublisher: PubSubPublisher,      // ← WalletService hata, PubSub aaya
    private val otpService: OtpService,
    private val mpinJwtService: MpinJwtService,
    @org.springframework.beans.factory.annotation.Value("\${youpi.auth.dummy.mobile:+919369016664}")
    private val dummyAuthMobile: String,
    @org.springframework.beans.factory.annotation.Value("\${youpi.auth.dummy.otp:123456}")
    private val dummyAuthOtp: String
) {

    private val log = LoggerFactory.getLogger(javaClass)
    private val secureRandom = SecureRandom()

    companion object {
        private const val MPIN_MAX_ATTEMPTS = 5
        private val MPIN_LOCKOUT_DURATION = Duration.ofMinutes(30)
        private val REFRESH_TOKEN_TTL = Duration.ofDays(30)
    }

    // Marks a device as trusted for a user right after it proves phone-number
    // possession via OTP/Firebase verification. Called from verifyOtp() and
    // verifyFirebaseToken() -- never from verifyMpin(), since MPIN alone
    // doesn't prove device identity (that's the whole point of this check).
    private suspend fun trustDevice(userId: UUID, deviceId: String?) {
        if (deviceId.isNullOrBlank()) return
        val existing = trustedDeviceRepo.findByUserIdAndDeviceId(userId, deviceId)
        if (existing == null) {
            trustedDeviceRepo.save(UserTrustedDeviceEntity(userId = userId, deviceId = deviceId))
            log.info("Device trusted for user {} (deviceId=****)", userId)
        } else {
            trustedDeviceRepo.touch(userId, deviceId)
        }
    }

    // ─────────── OTP Flow ───────────

    suspend fun sendOtp(mobile: String): Result<OtpSentResponse, AuthException> {
        val normalized = "+91${mobile.takeLast(10)}"

        if (normalized == dummyAuthMobile || dummyAuthMobile == "ALL" || dummyAuthMobile == "") {
            log.info("Bypassing OTP send for test mobile: {}", normalized)
            return Result.success(OtpSentResponse())
        }

        log.info("Sending OTP for login (mobile=****)")

        if (otpService.isLockedOut("LOGIN", normalized)) {
            return Result.failure(OtpLockedOutException(Instant.now().plusSeconds(OtpService.LOCKOUT_SECONDS)))
        }

        val otp = otpService.generateOtp()
        val hash = otpService.hashOtp(otp)
        otpService.storeOtp("LOGIN", normalized, hash)

        otpSessionRepo.save(
            OtpSessionEntity(
                mobile = normalized,
                otpHash = hash,
                purpose = "LOGIN",
                expiresAt = Instant.now().plusSeconds(OtpService.OTP_TTL_SECONDS)
            )
        )

        // TODO: Send via MSG91 SMS API
        log.info("OTP stored and SMS queued (mobile=****)")

        return Result.success(OtpSentResponse())
    }
    // ─────────── OTP  Verify Flow ───────────

    suspend fun verifyOtp(req: VerifyOtpRequest): Result<AuthResponse, AuthException> {
        val normalized = "+91${req.mobile.takeLast(10)}"
        val isDummyAuth = (req.otp == dummyAuthOtp) && (normalized == dummyAuthMobile || dummyAuthMobile == "ALL" || dummyAuthMobile == "")

        if (!isDummyAuth) {
            if (otpService.isLockedOut("LOGIN", normalized)) {
                return Result.failure(OtpLockedOutException(Instant.now().plusSeconds(OtpService.LOCKOUT_SECONDS)))
            }

            val storedHash = otpService.getStoredHash("LOGIN", normalized)
                ?: return Result.failure(OtpExpiredException())

            if (!otpService.verifyOtp(req.otp, storedHash)) {
                val attempts = otpService.incrementAttempts("LOGIN", normalized)
                val remaining = OtpService.MAX_ATTEMPTS - attempts
                return if (remaining <= 0) {
                    Result.failure(OtpLockedOutException(Instant.now().plusSeconds(OtpService.LOCKOUT_SECONDS)))
                } else {
                    Result.failure(OtpInvalidException(remaining))
                }
            }

            otpService.clearOtp("LOGIN", normalized)
        } else {
            log.info("Dummy authentication used for test mobile: {}", normalized)
        }

        var user = userRepo.findByMobile(normalized)
        val isNewUser = user == null

        if (isNewUser) {
            user = userRepo.save(UserEntity(mobile = normalized))
            log.info("New user created (userId={})", user.id)
            try {
                pubSubPublisher.publish(
                    "user-created",
                    mapOf(
                        "userId" to user.id.toString(),
                        "mobile" to normalized,
                        "walletType" to "NBFC"
                    )
                )
            } catch (e: Exception) {
                log.error("Failed to publish user-created event for userId={}: {}", user.id, e.message)
            }
        }

        val userId = user!!.id!!
        trustDevice(userId, req.deviceId)
        val accessToken = mpinJwtService.issueToken(userId, normalized, user.userType)
        val refreshToken = generateRefreshToken(userId, req.deviceId)
        val profileComplete = user.fullName != null && user.dateOfBirth != null
        val kycStatus = if (user.isKycVerified) "VERIFIED" else "PENDING"

        return Result.success(
            AuthResponse(
                accessToken = accessToken,
                refreshToken = refreshToken,
                userId = userId,
                isNewUser = isNewUser,
                profileComplete = profileComplete,
                kycStatus = kycStatus,
                userType = user.userType
            )
        )
    }

    // ─────────── OTP verify Flow In Firebase Token───────────
    suspend fun verifyFirebaseToken(
        idToken: String,
        deviceId: String?
    ): Result<AuthResponse, AuthException> {
        // 1. Verify the Firebase ID token
        val decoded = try {
            withContext(Dispatchers.IO) {
                com.google.firebase.auth.FirebaseAuth.getInstance().verifyIdToken(idToken)
            }
        } catch (e: Exception) {
            log.warn("Firebase ID token verification failed: {}", e.message)
            return Result.failure(FirebaseTokenInvalidException())
        }

        // 2. Extract phone number from the verified token
        val phone = decoded.claims["phone_number"] as? String
            ?: return Result.failure(FirebaseTokenInvalidException())
        val normalized = "+91${phone.takeLast(10)}"
        val firebaseUid = decoded.uid

        // 3. Find or create the user
        var user = userRepo.findByMobile(normalized)
        val isNewUser = user == null

        if (isNewUser) {
            user = userRepo.save(UserEntity(mobile = normalized, firebaseUid = firebaseUid))
            log.info("New user created via Firebase (userId={})", user.id)
            try {
                pubSubPublisher.publish(
                    "user-created",
                    mapOf(
                        "userId" to user.id.toString(),
                        "mobile" to normalized,
                        "walletType" to "NBFC"
                    )
                )
            } catch (e: Exception) {
                log.error("Failed to publish user-created event: {}", e.message)
            }
        } else if (user!!.firebaseUid == null) {
            // Link firebaseUid to an existing user created earlier via OTP
            user = userRepo.save(user.copy(firebaseUid = firebaseUid))
        }

        // 4. Issue app tokens (same as verifyOtp)
        val userId = user!!.id!!
        trustDevice(userId, deviceId)
        val accessToken = mpinJwtService.issueToken(userId, normalized, user.userType)
        val refreshToken = generateRefreshToken(userId, deviceId)
        val profileComplete = user.fullName != null && user.dateOfBirth != null
        val kycStatus = if (user.isKycVerified) "VERIFIED" else "PENDING"

        return Result.success(
            AuthResponse(
                accessToken = accessToken,
                refreshToken = refreshToken,
                userId = userId,
                isNewUser = isNewUser,
                profileComplete = profileComplete,
                kycStatus = kycStatus,
                userType = user.userType
            )
        )
    }

    // ─────────── MPIN Flow ───────────

    suspend fun setupMpin(userId: UUID, mpin: String) {
        val hash = BCrypt.withDefaults().hashToString(12, mpin.toCharArray())

        mpinRepo.upsert(
            userId = userId,
            mpinHash = hash,
            attempts = 0,
            lockedUntil = null,
            updatedAt = Instant.now()
        )

        log.info("MPIN set for user {}", userId)
    }

    suspend fun verifyMpin(req: MpinVerifyRequest): Result<AuthResponse, AuthException> {
        val normalized = "+91${req.mobile.takeLast(10)}"
        val user = userRepo.findByMobile(normalized) ?: return Result.failure(UserNotFoundException())

        if (!user.isActive) return Result.failure(UserInactiveException())

        val userId = user.id!!
        val mpinRecord = mpinRepo.findByUserId(userId) ?: return Result.failure(MpinNotSetException())

        if (mpinRecord.lockedUntil != null && mpinRecord.lockedUntil.isAfter(Instant.now())) {
            return Result.failure(MpinLockedOutException(mpinRecord.lockedUntil))
        }

        val result = BCrypt.verifyer().verify(req.mpin.toCharArray(), mpinRecord.mpinHash)
        if (!result.verified) {
            val newAttempts = mpinRecord.attempts + 1
            val lockedUntil = if (newAttempts >= MPIN_MAX_ATTEMPTS) {
                Instant.now().plus(MPIN_LOCKOUT_DURATION)
            } else null

            mpinRepo.upsert(
                userId = userId,
                mpinHash = mpinRecord.mpinHash,
                attempts = newAttempts,
                lockedUntil = lockedUntil,
                updatedAt = Instant.now()
            )

            return if (lockedUntil != null) {
                Result.failure(MpinLockedOutException(lockedUntil))
            } else {
                Result.failure(MpinMismatchException(MPIN_MAX_ATTEMPTS - newAttempts))
            }
        }

        mpinRepo.upsert(
            userId = userId,
            mpinHash = mpinRecord.mpinHash,
            attempts = 0,
            lockedUntil = null,
            updatedAt = Instant.now()
        )

        // MPIN was correct -- but that alone doesn't prove *this device* is
        // the account owner's. Only a device that already completed an OTP
        // verification (trustDevice() in verifyOtp/verifyFirebaseToken) is
        // allowed to log in via MPIN alone. Anything else gets bounced back
        // to OTP, same as an expired/locked MPIN would.
        val trustedDevice = trustedDeviceRepo.findByUserIdAndDeviceId(userId, req.deviceId)
        if (trustedDevice == null) {
            return Result.failure(DeviceNotTrustedException())
        }
        trustedDeviceRepo.touch(userId, req.deviceId)

        val accessToken = mpinJwtService.issueToken(userId, normalized, user.userType)
        val refreshToken = generateRefreshToken(userId, req.deviceId)

        return Result.success(
            AuthResponse(
                accessToken = accessToken,
                refreshToken = refreshToken,
                userId = userId,
                isNewUser = false,
                profileComplete = user.fullName != null,
                kycStatus = if (user.isKycVerified) "VERIFIED" else "PENDING",
                userType = user.userType
            )
        )
    }

    // ─────────── Refresh Token ───────────

    suspend fun refreshAccessToken(refreshToken: String): Result<AuthResponse, AuthException> {
        val hash = sha256(refreshToken)
        val tokenEntity = refreshTokenRepo.findByTokenHashAndRevokedFalse(hash)
            ?: return Result.failure(TokenRevokedException())

        if (tokenEntity.expiresAt.isBefore(Instant.now())) {
            return Result.failure(TokenExpiredException())
        }

        refreshTokenRepo.revokeById(tokenEntity.id!!)

        val user = userRepo.findById(tokenEntity.userId) ?: return Result.failure(UserNotFoundException())

        val newAccessToken = mpinJwtService.issueToken(user.id!!, user.mobile, user.userType)
        val newRefreshToken = generateRefreshToken(user.id, tokenEntity.deviceId)

        return Result.success(
            AuthResponse(
                accessToken = newAccessToken,
                refreshToken = newRefreshToken,
                userId = user.id,
                isNewUser = false,
                profileComplete = user.fullName != null,
                kycStatus = if (user.isKycVerified) "VERIFIED" else "PENDING",
                userType = user.userType
            )
        )
    }

    suspend fun logout(userId: UUID, refreshToken: String) {
        val hash = sha256(refreshToken)
        val tokenEntity = refreshTokenRepo.findByTokenHashAndRevokedFalse(hash)
        if (tokenEntity != null && tokenEntity.userId == userId) {
            refreshTokenRepo.revokeById(tokenEntity.id!!)
            log.info("User {} logged out", userId)
        }
    }

    // ─────────── Helpers ───────────

    private suspend fun generateRefreshToken(userId: UUID, deviceId: String?): String {
        val raw = UUID.randomUUID().toString() + secureRandom.nextLong().toString()
        val hash = sha256(raw)

        refreshTokenRepo.save(
            RefreshTokenEntity(
                userId = userId,
                tokenHash = hash,
                deviceId = deviceId,
                expiresAt = Instant.now().plus(REFRESH_TOKEN_TTL)
            )
        )

        return raw
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        return digest.digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}