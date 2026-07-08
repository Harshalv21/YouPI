package `in`.youpi.admin.service

import `in`.youpi.auth.repository.UserEntity
import `in`.youpi.auth.repository.UserRepository
import `in`.youpi.core.NotFoundException
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

/**
 * Admin service — KYC review, Smart Saver activation, BNPL/Loan decisions, user management.
 * All endpoints require ADMIN user type.
 */
@Service
class AdminService(
    private val userRepo: UserRepository
) {

    private val log = LoggerFactory.getLogger(javaClass)

    // ── User Management ──

    suspend fun listUsers(page: Int = 0, pageSize: Int = 20): List<UserSummary> {
        // TODO: Implement with proper pagination
        val users = mutableListOf<UserSummary>()
        userRepo.findAll().collect { user ->
            users.add(UserSummary(
                userId = user.id!!,
                mobile = user.mobile,
                fullName = user.fullName,
                userType = user.userType,
                isKycVerified = user.isKycVerified,
                isActive = user.isActive,
                createdAt = user.createdAt
            ))
        }
        return users.drop(page * pageSize).take(pageSize)
    }

    suspend fun getUserDetails(userId: UUID): UserSummary {
        val user = userRepo.findById(userId)
            ?: throw NotFoundException("User", userId.toString())

        return UserSummary(
            userId = user.id!!,
            mobile = user.mobile,
            fullName = user.fullName,
            userType = user.userType,
            isKycVerified = user.isKycVerified,
            isActive = user.isActive,
            createdAt = user.createdAt
        )
    }

    suspend fun updateUserType(userId: UUID, userType: String): UserSummary {
        val user = userRepo.findById(userId)
            ?: throw NotFoundException("User", userId.toString())

        val updated = userRepo.save(user.copy(userType = userType, updatedAt = Instant.now()))
        log.info("User {} type changed to {}", userId, userType)

        return UserSummary(
            userId = updated.id!!,
            mobile = updated.mobile,
            fullName = updated.fullName,
            userType = updated.userType,
            isKycVerified = updated.isKycVerified,
            isActive = updated.isActive,
            createdAt = updated.createdAt
        )
    }

    suspend fun toggleUserActive(userId: UUID, isActive: Boolean): UserSummary {
        val user = userRepo.findById(userId)
            ?: throw NotFoundException("User", userId.toString())

        val updated = userRepo.save(user.copy(isActive = isActive, updatedAt = Instant.now()))
        log.info("User {} active status changed to {}", userId, isActive)

        return UserSummary(
            userId = updated.id!!,
            mobile = updated.mobile,
            fullName = updated.fullName,
            userType = updated.userType,
            isKycVerified = updated.isKycVerified,
            isActive = updated.isActive,
            createdAt = updated.createdAt
        )
    }

    // ── Dashboard ──

    suspend fun getDashboard(): AdminDashboard {
        // TODO: Replace with proper aggregate queries
        var totalUsers = 0L
        userRepo.findAll().collect { totalUsers++ }

        return AdminDashboard(
            totalUsers = totalUsers,
            activeUsers = totalUsers, // placeholder
            kycPending = 0,
            bnplPending = 0,
            loanPending = 0,
            totalRecharges = 0,
            totalRevenue = BigDecimal.ZERO
        )
    }
}

data class UserSummary(
    val userId: UUID,
    val mobile: String,
    val fullName: String?,
    val userType: String,
    val isKycVerified: Boolean,
    val isActive: Boolean,
    val createdAt: Instant
)

data class AdminDashboard(
    val totalUsers: Long,
    val activeUsers: Long,
    val kycPending: Int,
    val bnplPending: Int,
    val loanPending: Int,
    val totalRecharges: Int,
    val totalRevenue: BigDecimal
)
