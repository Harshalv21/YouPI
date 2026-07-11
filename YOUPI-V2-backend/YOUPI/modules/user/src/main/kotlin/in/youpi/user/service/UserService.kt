package `in`.youpi.user.service

import `in`.youpi.auth.repository.UserEntity
import `in`.youpi.auth.repository.UserRepository
import `in`.youpi.core.NotFoundException
import `in`.youpi.core.Result
import `in`.youpi.security.EncryptionService
import `in`.youpi.user.domain.*
import `in`.youpi.user.repository.KycRecordEntity
import `in`.youpi.user.repository.KycRecordRepository
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.time.Instant
import java.util.UUID

/**
 * User profile management and KYC flow orchestration.
 * KYC follows a strict state machine: PENDING → AADHAAR_DONE → PAN_DONE → SELFIE_DONE → VERIFIED
 */
@Service
class UserService(
    private val userRepo: UserRepository,
    private val kycRepo: KycRecordRepository,
    private val encryptionService: EncryptionService
) {

    private val log = LoggerFactory.getLogger(javaClass)

    // ── Profile ──

    suspend fun getProfile(userId: UUID): UserProfileResponse {
        val user = userRepo.findById(userId)
            ?: throw NotFoundException("User", userId.toString())

        val kyc = kycRepo.findByUserId(userId)

        return UserProfileResponse(
            userId = user.id!!,
            mobile = user.mobile,
            fullName = user.fullName,
            email = user.email,
            dateOfBirth = user.dateOfBirth,
            isKycVerified = user.isKycVerified,
            kycStatus = kyc?.kycStatus ?: "PENDING",
            userType = user.userType
        )
    }

    suspend fun updateProfile(userId: UUID, req: UpdateProfileRequest): UserProfileResponse {
        val user = userRepo.findById(userId)
            ?: throw NotFoundException("User", userId.toString())

        val updated = userRepo.save(
            user.copy(
                fullName = req.fullName,
                email = req.email ?: user.email,
                dateOfBirth = req.dateOfBirth ?: user.dateOfBirth,
                updatedAt = Instant.now()
            )
        )

        val kyc = kycRepo.findByUserId(userId)

        return UserProfileResponse(
            userId = updated.id!!,
            mobile = updated.mobile,
            fullName = updated.fullName,
            email = updated.email,
            dateOfBirth = updated.dateOfBirth,
            isKycVerified = updated.isKycVerified,
            kycStatus = kyc?.kycStatus ?: "PENDING",
            userType = updated.userType
        )
    }

    // ── KYC Status ──

    suspend fun getKycStatus(userId: UUID): KycStatusResponse {
        val kyc = kycRepo.findByUserId(userId)

        return KycStatusResponse(
            userId = userId,
            kycStatus = kyc?.kycStatus ?: "PENDING",
            aadhaarVerified = kyc?.aadhaarVerified ?: false,
            panVerified = kyc?.panVerified ?: false,
            selfieUploaded = kyc?.selfieGcsPath != null,
            faceMatchScore = kyc?.faceMatchScore?.toDouble()
        )
    }

    // ── Step 1: Aadhaar Verification ──

    suspend fun initiateAadhaarOtp(userId: UUID, aadhaarNumber: String): Result<AadhaarOtpResponse, KycException> {
        val kyc = getOrCreateKyc(userId)

        // Validate state machine
        val currentStatus = KycStatus.valueOf(kyc.kycStatus)
        if (currentStatus != KycStatus.PENDING && currentStatus != KycStatus.REJECTED) {
            return Result.failure(KycStepOutOfOrderException(kyc.kycStatus, "AADHAAR_VERIFY"))
        }

        // Encrypt Aadhaar for storage
        val encrypted = encryptionService.encrypt(aadhaarNumber)
        val last4 = aadhaarNumber.takeLast(4)

        // Call Digio API for Aadhaar OTP
        // TODO: Integrate with DigioClient
        val digioRequestId = "digio_${UUID.randomUUID()}"

        kycRepo.save(
            kyc.copy(
                aadhaarEncrypted = encrypted,
                aadhaarLast4 = last4,
                digioRequestId = digioRequestId,
                updatedAt = Instant.now()
            )
        )

        log.info("Aadhaar OTP initiated for user {} (last4={})", userId, last4)

        return Result.success(AadhaarOtpResponse(digioRequestId = digioRequestId))
    }

    suspend fun verifyAadhaarOtp(userId: UUID, req: AadhaarVerifyRequest): Result<KycStatusResponse, KycException> {
        val kyc = kycRepo.findByUserId(userId)
            ?: return Result.failure(KycVerificationFailedException("KYC record not found"))

        // TODO: Call Digio API to verify OTP
        // For now, mark as verified
        val updated = kycRepo.save(
            kyc.copy(
                aadhaarVerified = true,
                aadhaarVerifiedAt = Instant.now(),
                kycStatus = "AADHAAR_DONE",
                updatedAt = Instant.now()
            )
        )

        log.info("Aadhaar verified for user {}", userId)
        return Result.success(toKycStatusResponse(userId, updated))
    }

    // ── Step 2: PAN Verification ──

    suspend fun verifyPan(userId: UUID, panNumber: String): Result<KycStatusResponse, KycException> {
        val kyc = kycRepo.findByUserId(userId)
            ?: return Result.failure(KycVerificationFailedException("KYC record not found"))

        val currentStatus = KycStatus.valueOf(kyc.kycStatus)
        if (!currentStatus.nextAllowed().contains(KycStatus.PAN_DONE)) {
            return Result.failure(KycStepOutOfOrderException(kyc.kycStatus, "PAN_VERIFY"))
        }

        // TODO: Call Karza API for PAN verification
        val karzaRequestId = "karza_${UUID.randomUUID()}"

        val updated = kycRepo.save(
            kyc.copy(
                panNumber = panNumber,
                panVerified = true,
                panVerifiedAt = Instant.now(),
                karzaRequestId = karzaRequestId,
                kycStatus = "PAN_DONE",
                updatedAt = Instant.now()
            )
        )

        log.info("PAN verified for user {}", userId)
        return Result.success(toKycStatusResponse(userId, updated))
    }

    // ── Step 3: Selfie + Face Match ──

    suspend fun uploadSelfie(userId: UUID, selfieBase64: String): Result<KycStatusResponse, KycException> {
        val kyc = kycRepo.findByUserId(userId)
            ?: return Result.failure(KycVerificationFailedException("KYC record not found"))

        val currentStatus = KycStatus.valueOf(kyc.kycStatus)
        if (!currentStatus.nextAllowed().contains(KycStatus.SELFIE_DONE)) {
            return Result.failure(KycStepOutOfOrderException(kyc.kycStatus, "SELFIE_UPLOAD"))
        }

        // TODO: Upload to GCS via FirebaseStorageClient
        val gcsPath = "users/$userId/selfie_${System.currentTimeMillis()}.jpg"

        // TODO: Face match scoring against Aadhaar photo
        val faceMatchScore = java.math.BigDecimal("95.50")

        val newStatus = if (faceMatchScore.toDouble() >= 70.0) "SELFIE_DONE" else "REJECTED"
        val rejectionReason = if (newStatus == "REJECTED") "Face match score below threshold" else null

        val updated = kycRepo.save(
            kyc.copy(
                selfieGcsPath = gcsPath,
                faceMatchScore = faceMatchScore,
                kycStatus = newStatus,
                rejectionReason = rejectionReason,
                updatedAt = Instant.now()
            )
        )

        // If all steps done, auto-verify
        if (newStatus == "SELFIE_DONE") {
            kycRepo.save(updated.copy(kycStatus = "VERIFIED", verifiedAt = Instant.now()))

            val user = userRepo.findById(userId)
            if (user != null) {
                userRepo.save(user.copy(isKycVerified = true, updatedAt = Instant.now()))
            }
            log.info("KYC fully verified for user {}", userId)
        }

        return Result.success(toKycStatusResponse(userId, updated))
    }

    // ── Helpers ──

    private suspend fun getOrCreateKyc(userId: UUID): KycRecordEntity {
        return kycRepo.findByUserId(userId)
            ?: kycRepo.save(KycRecordEntity(userId = userId))
    }

    private fun toKycStatusResponse(userId: UUID, kyc: KycRecordEntity): KycStatusResponse {
        return KycStatusResponse(
            userId = userId,
            kycStatus = kyc.kycStatus,
            aadhaarVerified = kyc.aadhaarVerified,
            panVerified = kyc.panVerified,
            selfieUploaded = kyc.selfieGcsPath != null,
            faceMatchScore = kyc.faceMatchScore?.toDouble()
        )
    }
}
