package `in`.youpi.auth.domain

import `in`.youpi.core.BaseException
import java.time.Instant
import java.util.UUID

// ── Request DTOs ──

data class SendOtpRequest(val mobile: String) {
    init {
        require(mobile.matches(Regex("^[6-9]\\d{9}$"))) { "Invalid mobile number" }
    }
    fun normalized(): String = "+91$mobile"
}

data class VerifyOtpRequest(
    val mobile: String,
    val otp: String,
    val deviceId: String? = null
)

data class MpinSetupRequest(val mpin: String) {
    init {
        require(mpin.matches(Regex("^\\d{4}$"))) { "MPIN must be exactly 4 digits" }
    }
}

data class MpinVerifyRequest(
    val mobile: String,
    val mpin: String,
    val deviceId: String
)

data class RefreshTokenRequest(val refreshToken: String)

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
    val idToken: String,
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