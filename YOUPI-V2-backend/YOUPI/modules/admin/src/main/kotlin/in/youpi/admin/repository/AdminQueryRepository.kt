package `in`.youpi.admin.repository

import `in`.youpi.auth.repository.UserEntity
import org.springframework.data.r2dbc.repository.Query
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.stereotype.Repository
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

/**
 * Read-only, cross-table aggregate/search queries for the admin panel.
 * Deliberately kept separate from UserRepository (the existing, simple
 * CRUD repository used by AdminService's KYC/userType/active-toggle
 * methods) -- those don't need custom SQL, these do.
 *
 * FIX: extends CoroutineCrudRepository<UserEntity, UUID> (was <Any, UUID>)
 * -- Spring Data R2DBC requires a properly @Table-annotated entity as the
 * generic type to recognize this as a valid repository at all; `Any`
 * caused it to be silently skipped, crashing app startup with
 * "No qualifying bean of type AdminQueryRepository". UserEntity is used
 * purely as a valid marker type here -- every @Query method below defines
 * its own actual return type (DashboardRow, AdminUserRow, etc.),
 * independent of the generic parameter.
 *
 * `users` table columns CONFIRMED from the existing AdminService.kt
 * skeleton: mobile, full_name, user_type, is_kyc_verified (boolean),
 * is_active (boolean), created_at.
 *
 * `recharge_orders` and `gold_reward_ledger` table/column names are still
 * NOT independently confirmed in this session -- verify against your
 * actual schema before running.
 */

data class DashboardRow(
    val totalUsers: Long,
    val activeToday: Long,
    val totalRevenue: BigDecimal,
    val successCount: Long,
    val totalCount: Long
)

data class TrendPoint(
    val day: java.time.LocalDate,
    val revenue: BigDecimal,
    val txnCount: Long
)

data class AdminUserRow(
    val id: UUID,
    val fullName: String?,
    val mobile: String,
    val isKycVerified: Boolean,
    val isActive: Boolean,
    val joinedAt: Instant,
    val totalRecharges: Long,
    val totalSpend: BigDecimal
)

data class AdminTransactionRow(
    val id: UUID,
    val userId: UUID,
    val userName: String?,
    val mobile: String,
    val operator: String,
    val circle: String,
    val amount: BigDecimal,
    val status: String,
    val createdAt: Instant
)

data class AdminGoldRow(
    val id: Long, // gold_reward_ledger.id is BIGSERIAL, not UUID -- was UUID here, broke row mapping
    val userId: UUID,
    val userName: String?,
    val rechargeAmount: BigDecimal,
    val coinsEarned: Int,
    val grams: BigDecimal,
    val createdAt: Instant
)

@Repository
interface AdminQueryRepository : CoroutineCrudRepository<UserEntity, UUID> {

    // ── Dashboard ──

    @Query("""
        SELECT
            (SELECT COUNT(*) FROM users) AS total_users,
            (SELECT COUNT(DISTINCT user_id) FROM recharge_orders WHERE created_at >= CURRENT_DATE) AS active_today,
            (SELECT COALESCE(SUM(plan_amount), 0) FROM recharge_orders WHERE status = 'RECHARGE_SUCCESS') AS total_revenue,
            (SELECT COUNT(*) FROM recharge_orders WHERE status = 'RECHARGE_SUCCESS') AS success_count,
            (SELECT COUNT(*) FROM recharge_orders) AS total_count
    """)
    suspend fun getDashboardTotals(): DashboardRow

    @Query("""
        SELECT
            DATE(created_at) AS day,
            COALESCE(SUM(plan_amount) FILTER (WHERE status = 'RECHARGE_SUCCESS'), 0) AS revenue,
            COUNT(*) AS txn_count
        FROM recharge_orders
        WHERE created_at >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY DATE(created_at)
        ORDER BY day ASC
    """)
    suspend fun getDailyTrend(): List<TrendPoint>

    // ── Users ──

    @Query("""
        SELECT
            u.id, u.full_name, u.mobile, u.is_kyc_verified, u.is_active, u.created_at AS joined_at,
            COUNT(r.id) AS total_recharges,
            COALESCE(SUM(r.plan_amount) FILTER (WHERE r.status = 'RECHARGE_SUCCESS'), 0) AS total_spend
        FROM users u
        LEFT JOIN recharge_orders r ON r.user_id = u.id
        WHERE (:search = '' OR u.full_name ILIKE '%' || :search || '%' OR u.mobile ILIKE '%' || :search || '%')
          AND (:kyc = 'ALL'
               OR (:kyc = 'VERIFIED' AND u.is_kyc_verified = TRUE)
               OR (:kyc = 'NOT_VERIFIED' AND u.is_kyc_verified = FALSE))
        GROUP BY u.id, u.full_name, u.mobile, u.is_kyc_verified, u.is_active, u.created_at
        ORDER BY u.created_at DESC
        LIMIT :pageSize OFFSET :offset
    """)
    suspend fun searchUsers(search: String, kyc: String, pageSize: Int, offset: Int): List<AdminUserRow>

    @Query("""
        SELECT COUNT(*) FROM users u
        WHERE (:search = '' OR u.full_name ILIKE '%' || :search || '%' OR u.mobile ILIKE '%' || :search || '%')
          AND (:kyc = 'ALL'
               OR (:kyc = 'VERIFIED' AND u.is_kyc_verified = TRUE)
               OR (:kyc = 'NOT_VERIFIED' AND u.is_kyc_verified = FALSE))
    """)
    suspend fun countUsers(search: String, kyc: String): Long

    // ── Transactions ──

    @Query("""
        SELECT r.id, r.user_id, u.full_name AS user_name, r.mobile_number AS mobile,
               r.operator, r.circle, r.plan_amount AS amount, r.status, r.created_at
        FROM recharge_orders r
        LEFT JOIN users u ON u.id = r.user_id
        WHERE (:search = '' OR u.full_name ILIKE '%' || :search || '%' OR r.mobile_number ILIKE '%' || :search || '%' OR r.id::text ILIKE '%' || :search || '%')
          AND (:status = 'ALL' OR r.status = :status)
        ORDER BY r.created_at DESC
        LIMIT :pageSize OFFSET :offset
    """)
    suspend fun searchTransactions(search: String, status: String, pageSize: Int, offset: Int): List<AdminTransactionRow>

    @Query("""
        SELECT COUNT(*) FROM recharge_orders r
        LEFT JOIN users u ON u.id = r.user_id
        WHERE (:search = '' OR u.full_name ILIKE '%' || :search || '%' OR r.mobile_number ILIKE '%' || :search || '%' OR r.id::text ILIKE '%' || :search || '%')
          AND (:status = 'ALL' OR r.status = :status)
    """)
    suspend fun countTransactions(search: String, status: String): Long

    // ── Gold Ledger ──

    @Query("""
        SELECT g.id, g.user_id, u.full_name AS user_name, g.recharge_amount,
               FLOOR(g.reward_value_rupees / 0.10)::INT AS coins_earned,
               COALESCE(g.gold_grams, 0) AS grams, g.created_at
        FROM gold_reward_ledger g
        LEFT JOIN users u ON u.id = g.user_id
        WHERE (:search = '' OR u.full_name ILIKE '%' || :search || '%')
        ORDER BY g.created_at DESC
        LIMIT :pageSize OFFSET :offset
    """)
    suspend fun searchGoldLedger(search: String, pageSize: Int, offset: Int): List<AdminGoldRow>

    @Query("""
        SELECT COUNT(*) FROM gold_reward_ledger g
        LEFT JOIN users u ON u.id = g.user_id
        WHERE (:search = '' OR u.full_name ILIKE '%' || :search || '%')
    """)
    suspend fun countGoldLedger(search: String): Long
}