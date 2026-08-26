package `in`.youpi.core

import java.util.UUID

// ── KYC status port ──
//
// Same reasoning as WalletDebitPort.kt -- lives in shared/core so a
// caller (e.g. InvestService, for "block gold purchase above ₹1000
// until KYC is done") can depend on just this interface instead of the
// concrete modules/user module, avoiding a circular Gradle dependency.
interface KycStatusPort {

    /**
     * True only if both PAN and bank account verification are complete
     * (kyc_records.panVerified && bankVerified). Mirrors the same
     * "authoritative backend status" check used by KycGuard on the
     * frontend (see kyc_guard.dart) -- this is the server-side
     * enforcement that a client-side gate alone cannot guarantee.
     */
    suspend fun isVerified(userId: UUID): Boolean
}