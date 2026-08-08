package `in`.youpi.admin.service

import `in`.youpi.admin.domain.*
import `in`.youpi.admin.repository.AdminQueryRepository
import `in`.youpi.auth.repository.UserRepository
import `in`.youpi.core.NotFoundException
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/**
 * Backs the standalone web admin panel (youpi_admin_panel.html) --
 * DELIBERATELY separate from the existing AdminService/AdminRouter (which
 * power in-app admin actions for mobile users with userType=ADMIN, auth'd
 * via the regular Firebase+MPIN flow). This service is reached through
 * AdminPanelRouter's own JWT-based auth (AdminJwtService), not through
 * requireAdmin()/FirebaseAuthFilter -- the web panel's login session and
 * the in-app admin session are two independent auth mechanisms by design,
 * see the chat history for the reasoning (avoiding needing a Firebase
 * phone-OTP UX in a browser for the owner/director).
 *
 * toggleUserActive() here is a small, deliberate duplication of the same
 * logic in the existing AdminService -- necessary because this service
 * can't call that one's endpoint (different auth scheme entirely), but
 * both ultimately just flip the same `is_active` column on the same
 * `users` table, so there's no data-consistency risk from having two
 * callers of the same simple update.
 */
@Service
class AdminPanelService(
    private val userRepo: UserRepository,
    private val queryRepo: AdminQueryRepository
) {
    private val log = LoggerFactory.getLogger(javaClass)

    suspend fun getDashboardStats(): DashboardStatsResponse {
        val totals = queryRepo.getDashboardTotals()
        val trend = queryRepo.getDailyTrend()

        val trendByDay = trend.associateBy { it.day }
        val last14Days = (13 downTo 0).map { LocalDate.now().minusDays(it.toLong()) }
        val revenueTrend = last14Days.map { trendByDay[it]?.revenue ?: BigDecimal.ZERO }
        val txnTrend = last14Days.map { trendByDay[it]?.txnCount ?: 0L }

        val successRate = if (totals.totalCount > 0) {
            BigDecimal(totals.successCount).multiply(BigDecimal(100))
                .divide(BigDecimal(totals.totalCount), 1, RoundingMode.HALF_UP)
                .toDouble()
        } else 0.0

        return DashboardStatsResponse(
            totalUsers = totals.totalUsers,
            activeToday = totals.activeToday,
            totalRevenue = totals.totalRevenue,
            successRate = successRate,
            revenueTrend = revenueTrend,
            txnTrend = txnTrend
        )
    }

    // kyc param: "ALL" | "VERIFIED" | "NOT_VERIFIED"
    suspend fun searchUsers(search: String, kyc: String, page: Int, pageSize: Int): PagedResponse<AdminUserSummary> {
        val offset = page * pageSize
        val rows = queryRepo.searchUsers(search.trim(), kyc, pageSize, offset)
        val total = queryRepo.countUsers(search.trim(), kyc)
        return PagedResponse(
            items = rows.map {
                AdminUserSummary(
                    id = it.id, fullName = it.fullName, mobile = it.mobile,
                    isKycVerified = it.isKycVerified, isActive = it.isActive, joinedAt = it.joinedAt,
                    totalRecharges = it.totalRecharges, totalSpend = it.totalSpend
                )
            },
            total = total
        )
    }

    suspend fun toggleUserActive(userId: UUID, isActive: Boolean): Boolean {
        val user = userRepo.findById(userId) ?: throw NotFoundException("User", userId.toString())
        userRepo.save(user.copy(isActive = isActive, updatedAt = Instant.now()))
        log.info("Admin panel action: user {} active status changed to {}", userId, isActive)
        return true
    }

    suspend fun getTransactions(search: String, status: String, page: Int, pageSize: Int): PagedResponse<AdminTransactionSummary> {
        val offset = page * pageSize
        val rows = queryRepo.searchTransactions(search.trim(), status, pageSize, offset)
        val total = queryRepo.countTransactions(search.trim(), status)
        return PagedResponse(
            items = rows.map {
                AdminTransactionSummary(
                    id = it.id.toString(), userId = it.userId, userName = it.userName, mobile = it.mobile,
                    operator = it.operator, circle = it.circle, amount = it.amount,
                    gateway = "Cashfree",
                    status = it.status, createdAt = it.createdAt
                )
            },
            total = total
        )
    }

    suspend fun getGoldLedger(search: String, page: Int, pageSize: Int): PagedResponse<AdminGoldLedgerEntry> {
        val offset = page * pageSize
        val rows = queryRepo.searchGoldLedger(search.trim(), pageSize, offset)
        val total = queryRepo.countGoldLedger(search.trim())
        return PagedResponse(
            items = rows.map {
                AdminGoldLedgerEntry(
                    id = it.id.toString(), userId = it.userId, userName = it.userName,
                    rechargeAmount = it.rechargeAmount, coinsEarned = it.coinsEarned,
                    grams = it.grams, createdAt = it.createdAt
                )
            },
            total = total
        )
    }
}