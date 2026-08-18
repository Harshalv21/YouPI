package `in`.youpi.user.domain

import `in`.youpi.core.BaseException
import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import java.time.LocalDate
import java.util.UUID

// ── Request DTOs ──
// NOTE: enforced via awaitValidatedBody<T>() in the router, not automatically
// (functional coRouter handlers, not @RestController -- see shared/core
// RequestValidation.kt).

data class UpdateProfileRequest(
    @field:Size(max = 100, message = "fullName too long")
    val fullName: String? = null,
    @field:Email(message = "Invalid email")
    @field:Size(max = 254, message = "email too long")
    val email: String? = null,
    val dateOfBirth: LocalDate? = null
)

data class UpdateFcmTokenRequest(
    @field:NotBlank(message = "token is required")
    @field:Size(max = 4096, message = "token too long")
    val token: String
)

data class AadhaarOtpRequest(
    @field:Pattern(regexp = "^\\d{12}$", message = "Invalid Aadhaar number")
    val aadhaarNumber: String
) {
    init {
        require(aadhaarNumber.matches(Regex("^\\d{12}$"))) { "Invalid Aadhaar number" }
    }
}

data class AadhaarVerifyRequest(
    @field:Pattern(regexp = "^\\d{12}$", message = "Invalid Aadhaar number")
    val aadhaarNumber: String,
    @field:Pattern(regexp = "^\\d{4,6}$", message = "OTP must be 4-6 digits")
    val otp: String,
    @field:NotBlank(message = "digioRequestId is required")
    val digioRequestId: String
)

data class PanVerifyRequest(
    @field:Pattern(regexp = "^[A-Z]{5}\\d{4}[A-Z]$", message = "Invalid PAN format")
    val panNumber: String
) {
    init {
        require(panNumber.matches(Regex("^[A-Z]{5}\\d{4}[A-Z]$"))) { "Invalid PAN format" }
    }
}

data class SelfieUploadRequest(
    @field:NotBlank(message = "selfieBase64 is required")
    val selfieBase64: String
)

// ── Response DTOs ──

data class UserProfileResponse(
    val userId: UUID,
    val mobile: String,
    val fullName: String?,
    val email: String?,
    val dateOfBirth: LocalDate?,
    val isKycVerified: Boolean,
    val kycStatus: String,
    val userType: String
)

data class KycStatusResponse(
    val userId: UUID,
    val kycStatus: String,
    val aadhaarVerified: Boolean,
    val panVerified: Boolean,
    val selfieUploaded: Boolean,
    val faceMatchScore: Double?
)

data class AadhaarOtpResponse(
    val digioRequestId: String,
    val message: String = "Aadhaar OTP sent"
)

// ── KYC State Machine ──
enum class KycStatus {
    PENDING, AADHAAR_DONE, PAN_DONE, SELFIE_DONE, VERIFIED, REJECTED;

    fun nextAllowed(): Set<KycStatus> = when (this) {
        PENDING -> setOf(AADHAAR_DONE)
        AADHAAR_DONE -> setOf(PAN_DONE)
        PAN_DONE -> setOf(SELFIE_DONE)
        SELFIE_DONE -> setOf(VERIFIED, REJECTED)
        VERIFIED -> emptySet()
        REJECTED -> setOf(PENDING) // Can retry
    }
}

// ── Sealed KYC Exceptions ──

sealed class KycException(
    code: String,
    message: String,
    httpStatus: Int = 400
) : BaseException(code, message) {
    override val httpStatus: Int = httpStatus
}

class KycNotVerifiedException : KycException("KYC_REQUIRED", "KYC verification required before this operation.", 403)
class KycStepOutOfOrderException(val currentStep: String, val attempted: String) : KycException(
    "KYC_STEP_INVALID", "Cannot proceed to $attempted from $currentStep.", 409
)
class KycVerificationFailedException(val reason: String) : KycException(
    "KYC_VERIFICATION_FAILED", "KYC verification failed: $reason", 422
)
class KycAlreadyVerifiedException : KycException(
    "KYC_ALREADY_VERIFIED", "KYC is already verified.", 409
)