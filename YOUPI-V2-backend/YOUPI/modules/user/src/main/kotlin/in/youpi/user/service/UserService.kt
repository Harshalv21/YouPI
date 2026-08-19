package `in`.youpi.user.service

import `in`.youpi.auth.repository.UserEntity
import `in`.youpi.auth.repository.UserRepository
import `in`.youpi.core.NotFoundException
import `in`.youpi.core.Result
import `in`.youpi.core.ValidationException
import `in`.youpi.security.EncryptionService
import `in`.youpi.user.domain.*
import `in`.youpi.user.eko.EkoClient
import `in`.youpi.user.repository.KycRecordEntity
import `in`.youpi.user.repository.KycRecordRepository
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.time.Instant
import java.util.UUID

/**
 * User profile management and KYC flow orchestration.
 * KYC follows a strict state machine: PENDING → AADHAAR_DONE → PAN_DONE → SELFIE_DONE → VERIFIED
 * Bank account verification (via Eko) is a separate flag alongside this state machine,
 * not part of the sequence -- see verifyBankAccount() below.
 */
@Service
class UserService(
    private val userRepo: UserRepository,
    private val kycRepo: KycRecordRepository,
    private val encryptionService: EncryptionService,
    private val ekoClient: EkoClient // ← NEW: replaces Karza (PAN) stub, also does bank verification
) {

    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        private val EMAIL_REGEX = Regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$")
    }

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

    suspend fun updateFcmToken(userId: UUID, fcmToken: String) {
        if (fcmToken.isBlank()) return
        userRepo.updateFcmToken(userId, fcmToken)
    }

    suspend fun updateProfile(userId: UUID, req: UpdateProfileRequest): UserProfileResponse {
        val user = userRepo.findById(userId)
            ?: throw NotFoundException("User", userId.toString())

        if (user.email == null && req.email.isNullOrBlank()) {
            throw ValidationException("email", "Email is required to complete your profile")
        }
        if (req.email != null && !req.email.matches(EMAIL_REGEX)) {
            throw ValidationException("email", "Invalid email format")
        }

        val updated = userRepo.save(
            user.copy(
                fullName = req.fullName ?: user.fullName,
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
        return toKycStatusResponse(userId, kyc)
    }

    // ── Step 1: Aadhaar Verification ── UNCHANGED -- still Digio, not part of this Eko change

    suspend fun initiateAadhaarOtp(userId: UUID, aadhaarNumber: String): Result<AadhaarOtpResponse, KycException> {
        val kyc = getOrCreateKyc(userId)

        val currentStatus = KycStatus.valueOf(kyc.kycStatus)
        if (currentStatus != KycStatus.PENDING && currentStatus != KycStatus.REJECTED) {
            return Result.failure(KycStepOutOfOrderException(kyc.kycStatus, "AADHAAR_VERIFY"))
        }

        val encrypted = encryptionService.encrypt(aadhaarNumber)
        val last4 = aadhaarNumber.takeLast(4)

        // TODO: Integrate with DigioClient -- unchanged, out of scope for this Eko change
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

        // TODO: Call Digio API to verify OTP -- unchanged, out of scope for this Eko change
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

    // ── Step 2: PAN Verification — NOW VIA EKO (was Karza stub) ──

    suspend fun verifyPan(userId: UUID, panNumber: String): Result<KycStatusResponse, KycException> {
        val kyc = kycRepo.findByUserId(userId)
            ?: return Result.failure(KycVerificationFailedException("KYC record not found"))

        val currentStatus = KycStatus.valueOf(kyc.kycStatus)
        if (!currentStatus.nextAllowed().contains(KycStatus.PAN_DONE)) {
            return Result.failure(KycStepOutOfOrderException(kyc.kycStatus, "PAN_VERIFY"))
        }

        val ekoResult = try {
            ekoClient.verifyPan(panNumber)
        } catch (e: Exception) {
            log.error("Eko PAN verification failed for user {}: {}", userId, e.message)
            return Result.failure(KycVerificationFailedException("PAN verification service unavailable: ${e.message}"))
        }

        if (!ekoResult.success) {
            log.warn("Eko PAN verification returned unsuccessful for user {}", userId)
            return Result.failure(KycVerificationFailedException("PAN could not be verified"))
        }

        val updated = kycRepo.save(
            kyc.copy(
                panNumber = panNumber,
                panVerified = true,
                panVerifiedAt = Instant.now(),
                panHolderName = ekoResult.nameOnPan,
                ekoPanRequestId = ekoResult.upstreamRrn ?: ekoResult.rawResponse.hashCode().toString(),
                kycStatus = "PAN_DONE",
                updatedAt = Instant.now()
            )
        )

        log.info("PAN verified via Eko for user {}", userId)
        return Result.success(toKycStatusResponse(userId, updated))
    }

    // ── NEW: Bank Account Verification (via Eko) ──
    //
    // Net-new step -- no prior vendor existed for this. Tracked as its own
    // flag (bankVerified) rather than folded into the Aadhaar->PAN->Selfie
    // state machine, since it doesn't currently gate anything else. If a
    // future requirement needs bank verification to be mandatory before
    // some action (e.g. wallet withdrawal, loan disbursement), gate that
    // action on kyc.bankVerified directly rather than threading a new
    // state into KycStatus.
    suspend fun verifyBankAccount(userId: UUID, req: BankAccountVerifyRequest): Result<KycStatusResponse, KycException> {
        val kyc = kycRepo.findByUserId(userId)
            ?: return Result.failure(KycVerificationFailedException("KYC record not found"))

        val ekoResult = try {
            ekoClient.verifyBankAccount(req.accountNumber, req.ifsc)
        } catch (e: Exception) {
            log.error("Eko bank account verification failed for user {}: {}", userId, e.message)
            return Result.failure(KycVerificationFailedException("Bank verification service unavailable: ${e.message}"))
        }

        if (!ekoResult.success) {
            log.warn("Eko bank account verification returned unsuccessful for user {}", userId)
            return Result.failure(KycVerificationFailedException("Bank account could not be verified"))
        }

        val updated = kycRepo.save(
            kyc.copy(
                bankAccountLast4 = req.accountNumber.takeLast(4),
                bankIfsc = req.ifsc,
                bankAccountHolderName = ekoResult.accountHolderName,
                bankName = ekoResult.bankName,
                bankBranch = ekoResult.branch,
                bankVerified = true,
                bankVerifiedAt = Instant.now(),
                ekoBankRequestId = ekoResult.rawResponse.hashCode().toString(), // TODO: use utr from EkoBankVerifyResult once confirmed stable/unique enough to serve as request id
                updatedAt = Instant.now()
            )
        )

        log.info("Bank account verified via Eko for user {}", userId)
        return Result.success(toKycStatusResponse(userId, updated))
    }

    // ── Step 3: Selfie + Face Match ── UNCHANGED

    suspend fun uploadSelfie(userId: UUID, selfieBase64: String): Result<KycStatusResponse, KycException> {
        val kyc = kycRepo.findByUserId(userId)
            ?: return Result.failure(KycVerificationFailedException("KYC record not found"))

        val currentStatus = KycStatus.valueOf(kyc.kycStatus)
        if (!currentStatus.nextAllowed().contains(KycStatus.SELFIE_DONE)) {
            return Result.failure(KycStepOutOfOrderException(kyc.kycStatus, "SELFIE_UPLOAD"))
        }

        val gcsPath = "users/$userId/selfie_${System.currentTimeMillis()}.jpg"
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

    private fun toKycStatusResponse(userId: UUID, kyc: KycRecordEntity?): KycStatusResponse {
        return KycStatusResponse(
            userId = userId,
            kycStatus = kyc?.kycStatus ?: "PENDING",
            aadhaarVerified = kyc?.aadhaarVerified ?: false,
            panVerified = kyc?.panVerified ?: false,
            selfieUploaded = kyc?.selfieGcsPath != null,
            faceMatchScore = kyc?.faceMatchScore?.toDouble(),
            panHolderName = kyc?.panHolderName,
            bankVerified = kyc?.bankVerified ?: false,
            bankAccountHolderName = kyc?.bankAccountHolderName
        )
    }
}