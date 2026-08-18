package `in`.youpi.auth.domain

import `in`.youpi.core.BaseException
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import java.time.Instant
import java.util.UUID

// ── Request DTOs ──
// NOTE: @field:... annotations here are enforced via awaitValidatedBody<T>()
// in the router (see shared/core RequestValidation.kt) -- NOT automatically,
// since this app uses functional coRouter handlers, not @RestController.
// The existing `init { require(...) }` blocks are kept as a defense-in-depth
// second layer (they also fire on any direct construction outside HTTP,
// e.g. in tests/services), but the annotations are now the single
// documented source of truth for what's a valid request.

data class SendOtpRequest(
    @field:Pattern(regexp = "^[6-9]\\d{9}$", message = "Invalid mobile number")
    val mobile: String
) {
    init {
        require(mobile.matches(Regex("^[6-9]\\d{9}$"))) { "Invalid mobile number" }
    }
    fun normalized(): String = "+91$mobile"
}

data class VerifyOtpRequest(
    @field:Pattern(regexp = "^[6-9]\\d{9}$", message = "Invalid mobile number")
    val mobile: String,
    @field:Pattern(regexp = "^\\d{4,6}$", message = "OTP must be 4-6 digits")
    val otp: String,
    @field:Size(max = 200, message = "deviceId too long")
    val deviceId: String? = null
)

data class MpinSetupRequest(
    @field:Pattern(regexp = "^\\d{4}$", message = "MPIN must be exactly 4 digits")
    val mpin: String
) {
    init {
        require(mpin.matches(Regex("^\\d{4}$"))) { "MPIN must be exactly 4 digits" }
    }
}

data class MpinVerifyRequest(
    @field:Pattern(regexp = "^[6-9]\\d{9}$", message = "Invalid mobile number")
    val mobile: String,
    @field:Pattern(regexp = "^\\d{4}$", message = "MPIN must be exactly 4 digits")
    val mpin: String,
    @field:NotBlank(message = "deviceId is required")
    @field:Size(max = 200, message = "deviceId too long")
    val deviceId: String
)

data class RefreshTokenRequest(
    @field:NotBlank(message = "refreshToken is required")
    val refreshToken: String
)

// ── Response DTOs ──

data class AuthResponse(
    val accessToken: String,
    val refreshToken: String,
    val userId: UUID,
    val isNewUser: Boolean,
    val profileComplete: Boolean,
    val kycStatus: String,
    val userType: String
)

data class OtpSentResponse(
    val message: String = "OTP sent successfully",
    val expiresInSeconds: Int = 300
)

// ── Sealed Exceptions ──

sealed class AuthException(
    code: String,
    message: String,
    httpStatus: Int = 400
) : BaseException(code, message) {
    override val httpStatus: Int = httpStatus
}

data class FirebaseVerifyRequest(
    @field:NotBlank(message = "idToken is required")
    val idToken: String,
    @field:Size(max = 200, message = "deviceId too long")
    val deviceId: String? = null
)
class FirebaseTokenInvalidException :
    AuthException("FIREBASE_TOKEN_INVALID", "Invalid or expired Firebase token.", 401)
class OtpExpiredException : AuthException("OTP_EXPIRED", "OTP has expired. Please request a new one.")
class OtpInvalidException(val attemptsRemaining: Int) : AuthException(
    "OTP_INVALID", "Invalid OTP. $attemptsRemaining attempts remaining."
)
class OtpLockedOutException(val unlocksAt: Instant) : AuthException(
    "OTP_LOCKED", "Too many failed attempts. Try again after ${unlocksAt}.", 429
)
class MpinMismatchException(val attemptsRemaining: Int) : AuthException(
    "MPIN_INVALID", "Invalid MPIN. $attemptsRemaining attempts remaining."
)
class MpinLockedOutException(val unlocksAt: Instant) : AuthException(
    "MPIN_LOCKED", "MPIN locked. Try again after ${unlocksAt}.", 429
)
class MpinNotSetException : AuthException("MPIN_NOT_SET", "MPIN not configured for this user.")
class DeviceNotTrustedException : AuthException(
    "DEVICE_NOT_TRUSTED", "This device isn't recognized. Please verify via OTP to continue.", 403
)
class TokenExpiredException : AuthException("TOKEN_EXPIRED", "Token has expired.", 401)
class TokenRevokedException : AuthException("TOKEN_REVOKED", "Token has been revoked.", 401)
class UserNotFoundException : AuthException("USER_NOT_FOUND", "User not found.", 404)
class UserInactiveException : AuthException("USER_INACTIVE", "User account is inactive.", 403)