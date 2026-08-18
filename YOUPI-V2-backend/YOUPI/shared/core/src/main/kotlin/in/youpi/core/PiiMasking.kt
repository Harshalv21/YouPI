package `in`.youpi.core

/**
 * Consistent PII masking for log lines.
 *
 * AuthService already fully redacts mobile numbers in its own logs
 * ("mobile=****") since a login flow has no operational need to see any
 * part of it. Other flows -- recharge, A1Topup delivery -- routinely need
 * to correlate a specific log line with a support ticket ("user says their
 * 9876543210 recharge failed"), so full redaction there just makes
 * debugging harder without adding real protection (support already has the
 * number from the ticket). Last-4 masking is the same tradeoff already
 * used for Aadhaar (see UserService's `aadhaarLast4`) -- enough to
 * correlate, not enough to reconstruct the full number from logs alone.
 *
 * Cloud Logging is readable by anyone with log-viewer IAM, not just
 * on-call engineers, so this is a real boundary, not just style.
 */
fun maskMobile(mobile: String?): String {
    if (mobile.isNullOrBlank()) return "unknown"
    val digitsOnly = mobile.filter { it.isDigit() }
    if (digitsOnly.length < 4) return "****"
    return "******" + digitsOnly.takeLast(4)
}