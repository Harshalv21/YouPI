package `in`.youpi.core

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Locale

/**
 * Value class wrapping BigDecimal for all monetary amounts.
 * NEVER use Double/Float for money in a fintech app.
 *
 * Default scale: 2 for INR, 6 for gold grams.
 */
@JvmInline
value class Money private constructor(val amount: BigDecimal) : Comparable<Money> {

    operator fun plus(other: Money): Money = Money(amount.add(other.amount).setScale(amount.scale(), RoundingMode.HALF_EVEN))
    operator fun minus(other: Money): Money = Money(amount.subtract(other.amount).setScale(amount.scale(), RoundingMode.HALF_EVEN))
    operator fun times(factor: BigDecimal): Money = Money(amount.multiply(factor).setScale(amount.scale(), RoundingMode.HALF_EVEN))
    operator fun times(factor: Int): Money = times(BigDecimal(factor))

    fun isZero(): Boolean = amount.compareTo(BigDecimal.ZERO) == 0
    fun isPositive(): Boolean = amount > BigDecimal.ZERO
    fun isNegative(): Boolean = amount < BigDecimal.ZERO

    /** Convert INR to paise for Razorpay (which accepts amount in smallest currency unit) */
    fun toPaise(): Long = amount.multiply(BigDecimal(100)).setScale(0, RoundingMode.HALF_EVEN).toLong()

    fun toDouble(): Double = amount.toDouble()

    override fun compareTo(other: Money): Int = amount.compareTo(other.amount)

    override fun toString(): String = "₹${INR_FORMATTER.format(amount)}"

    companion object {
        private val INR_FORMATTER = NumberFormat.getNumberInstance(Locale("en", "IN")).apply {
            minimumFractionDigits = 2
            maximumFractionDigits = 2
        }

        val ZERO = Money(BigDecimal.ZERO.setScale(2))

        /** Standard INR money with 2 decimal places */
        fun inr(amount: BigDecimal): Money = Money(amount.setScale(2, RoundingMode.HALF_EVEN))
        fun inr(amount: Long): Money = inr(BigDecimal(amount))
        fun inr(amount: String): Money = inr(BigDecimal(amount))
        fun inr(amount: Double): Money = inr(BigDecimal.valueOf(amount))

        /** Gold grams with 6 decimal places */
        fun grams(amount: BigDecimal): Money = Money(amount.setScale(6, RoundingMode.FLOOR))
        fun grams(amount: String): Money = grams(BigDecimal(amount))

        /** Create from Razorpay paise */
        fun fromPaise(paise: Long): Money = inr(BigDecimal(paise).divide(BigDecimal(100), 2, RoundingMode.HALF_EVEN))
    }
}
