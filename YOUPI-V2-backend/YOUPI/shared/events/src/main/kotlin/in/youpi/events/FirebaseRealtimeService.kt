package `in`.youpi.events

import com.google.firebase.FirebaseApp
import com.google.firebase.database.FirebaseDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.time.Instant
import java.util.UUID

/**
 * Firebase Realtime Database service — pushes real-time status updates
 * to the Flutter client for immediate UI reactivity.
 *
 * Paths:
 *   /recharge-status/{orderId}  — recharge processing status
 *   /gold-holdings/{userId}     — gold balance updates
 *   /bnpl-status/{userId}       — BNPL application status
 *   /loan-status/{userId}       — Loan application status
 *   /gold-price                 — latest 24K gold rate
 */
@Service
class FirebaseRealtimeService {

    private val log = LoggerFactory.getLogger(javaClass)

    private val db: FirebaseDatabase? by lazy {
        try {
            FirebaseDatabase.getInstance(FirebaseApp.getInstance())
        } catch (e: Exception) {
            log.warn("Firebase Realtime DB not available: {}", e.message)
            null
        }
    }

    // ── Recharge Status ──

    suspend fun pushRechargeStatus(orderId: UUID, status: RechargeStatusUpdate) {
        write("recharge-status/$orderId", status)
    }

    // ── Gold Holdings ──

    suspend fun pushGoldHoldings(userId: UUID, holdings: GoldHoldingsUpdate) {
        write("gold-holdings/$userId", holdings)
    }

    // ── Gold Price ──

    suspend fun pushGoldPrice(price: GoldPriceUpdate) {
        write("gold-price", price)
    }

    // ── BNPL Status ──

    suspend fun pushBnplStatus(userId: UUID, status: BnplStatusUpdate) {
        write("bnpl-status/$userId", status)
    }

    // ── Loan Status ──

    suspend fun pushLoanStatus(userId: UUID, status: LoanStatusUpdate) {
        write("loan-status/$userId", status)
    }

    // ── Internal ──

    private suspend fun write(path: String, data: Any) {
        val database = db ?: run {
            log.warn("Firebase RTDB not initialized, skipping write to: {}", path)
            return
        }

        try {
            withContext(Dispatchers.IO) {
                database.getReference(path).setValueAsync(data).get()
            }
            log.debug("Firebase RTDB write: path={}", path)
        } catch (e: Exception) {
            log.error("Firebase RTDB write failed: path={}, error={}", path, e.message, e)
        }
    }
}

// ── Data Classes for Firebase RTDB ──

data class RechargeStatusUpdate(
    val status: String,
    val operatorTxnId: String? = null,
    val message: String? = null,
    val updatedAt: String = Instant.now().toString()
)

data class GoldHoldingsUpdate(
    val totalGrams: Double,
    val totalInvestedInr: Double,
    val currentValueInr: Double,
    val lastBuyAt: String? = null,
    val updatedAt: String = Instant.now().toString()
)

data class GoldPriceUpdate(
    val rate24kPerGram: Double,
    val provider: String = "SafeGold",
    val updatedAt: String = Instant.now().toString()
)

data class BnplStatusUpdate(
    val status: String,
    val approvedLimit: Double? = null,
    val rejectionReason: String? = null,
    val updatedAt: String = Instant.now().toString()
)

data class LoanStatusUpdate(
    val status: String,
    val approvedAmount: Double? = null,
    val interestRate: Double? = null,
    val monthlyEmi: Double? = null,
    val rejectionReason: String? = null,
    val updatedAt: String = Instant.now().toString()
)
