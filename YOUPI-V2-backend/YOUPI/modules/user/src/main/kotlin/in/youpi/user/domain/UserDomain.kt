package `in`.youpi.user.domain

import `in`.youpi.core.BaseException
import java.time.LocalDate
import java.util.UUID

// ── Request DTOs ──

data class UpdateProfileRequest(
    val fullName: String,
    val email: String? = null,
    val dateOfBirth: LocalDate? = null
)

data class AadhaarOtpRequest(val aadhaarNumber: String) {
    init {
        require(aadhaarNumber.matches(Regex("^\\d{12}$"))) { "Invalid Aadhaar number" }
    }
}

data class AadhaarVerifyRequest(
    val aadhaarNumber: String,
    val otp: String,
    val digioRequestId: String
)

data class PanVerifyRequest(val panNumber: String) {
    init {
        require(panNumber.matches(Regex("^[A-Z]{5}\\d{4}[A-Z]$"))) { "Invalid PAN format" }
    }
}

data class SelfieUploadRequest(val selfieBase64: String)

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
