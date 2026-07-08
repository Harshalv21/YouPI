package `in`.youpi.user.repository

import org.springframework.data.annotation.Id
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

@Table("kyc_records")
data class KycRecordEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val aadhaarEncrypted: ByteArray? = null,
    val aadhaarLast4: String? = null,
    val aadhaarVerified: Boolean = false,
    val aadhaarVerifiedAt: Instant? = null,
    val panNumber: String? = null,
    val panVerified: Boolean = false,
    val panVerifiedAt: Instant? = null,
    val selfieGcsPath: String? = null,
    val panFrontGcs: String? = null,
    val panBackGcs: String? = null,
    val aadhaarFrontGcs: String? = null,
    val aadhaarBackGcs: String? = null,
    val faceMatchScore: BigDecimal? = null,
    val kycStatus: String = "PENDING",
    val rejectionReason: String? = null,
    val verifiedAt: Instant? = null,
    val digioRequestId: String? = null,
    val karzaRequestId: String? = null,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
) {
    override fun equals(other: Any?): Boolean = other is KycRecordEntity && id == other.id
    override fun hashCode(): Int = id.hashCode()
}

interface KycRecordRepository : CoroutineCrudRepository<KycRecordEntity, UUID> {
    suspend fun findByUserId(userId: UUID): KycRecordEntity?
}

@Table("smart_saver_documents")
data class SmartSaverDocumentEntity(
    @Id val id: UUID? = null,
    val userId: UUID,
    val docType: String,
    val gcsPath: String,
    val status: String = "PENDING",
    val rejectionReason: String? = null,
    val reviewedBy: UUID? = null,
    val reviewedAt: Instant? = null,
    val createdAt: Instant = Instant.now()
)

interface SmartSaverDocumentRepository : CoroutineCrudRepository<SmartSaverDocumentEntity, UUID> {
    suspend fun findAllByUserId(userId: UUID): List<SmartSaverDocumentEntity>
    suspend fun findAllByStatus(status: String): List<SmartSaverDocumentEntity>
}
