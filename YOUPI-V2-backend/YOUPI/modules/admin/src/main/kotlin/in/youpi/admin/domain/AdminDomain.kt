package `in`.youpi.admin.domain

import `in`.youpi.core.BaseException
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

// ── Auth ──

data class AdminLoginRequest(
    val email: String,
    val password: String
)

data class AdminLoginResponse(
    val token: String,
    val adminName: String,
    val role: String
)

// ── Dashboard ──

data class DashboardStatsResponse(
    val totalUsers: Long,
    val activeToday: Long,
    val totalRevenue: BigDecimal,
    val successRate: Double,
    // last 14 days, oldest first -- matches Sparkline component's expected order
    val revenueTrend: List<BigDecimal>,
    val txnTrend: List<Long>
)

// ── Users ──
//
// Field names/types here match the REAL UserEntity (confirmed from the
// existing AdminService.kt skeleton) -- fullName (not "name"), no email
// field, isKycVerified/isActive are booleans (not multi-state strings).

data class AdminUserSummary(
    val id: UUID,
    val fullName: String?,
    val mobile: String,
    val isKycVerified: Boolean,
    val isActive: Boolean,
    val joinedAt: Instant,
    val totalRecharges: Long,
    val totalSpend: BigDecimal
)

data class PagedResponse<T>(
    val items: List<T>,
    val total: Long
)

// The admin panel's Block/Unblock action calls PATCH /users/{id}/status
// with a plain boolean body { "isActive": false }, handled by
// AdminPanelService.toggleUserActive() via AdminPanelRouter's
// handleUpdateUserStatus() -- separate from the existing AdminService.
data class UpdateUserActiveRequest(
    val isActive: Boolean
)

// ── Transactions ──

data class AdminTransactionSummary(
    val id: String,
    val userId: UUID,
    val userName: String?,
    val mobile: String,
    val operator: String,
    val circle: String,
    val amount: BigDecimal,
    val gateway: String,
    val status: String,
    val createdAt: Instant
)

// ── Gold Ledger ──

data class AdminGoldLedgerEntry(
    val id: String,
    val userId: UUID,
    val userName: String?,
    val rechargeAmount: BigDecimal,
    val coinsEarned: Int,
    val grams: BigDecimal,
    val createdAt: Instant
)

// ── Exceptions ──

sealed class AdminException(code: String, message: String, httpStatus: Int = 400)
    : BaseException(code, message) { override val httpStatus: Int = httpStatus }

class AdminInvalidCredentialsException : AdminException(
    "ADMIN_INVALID_CREDENTIALS", "Invalid email or password.", 401
)
class AdminUnauthorizedException : AdminException(
    "ADMIN_UNAUTHORIZED", "Admin authentication required.", 401
)
class AdminUserNotFoundException(userId: UUID) : AdminException(
    "ADMIN_USER_NOT_FOUND", "User $userId not found.", 404
)