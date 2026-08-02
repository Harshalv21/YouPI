package `in`.youpi.events

import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.Message
import com.google.firebase.messaging.Notification
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.math.BigDecimal

/**
 * Sends FCM push notifications directly to a user's device.
 *
 * Built specifically to close the "recharge confirmed but the app was
 * already closed" gap: emi_selection_screen.dart's synchronous polling
 * (recharge_viewmodel.dart, ~50s) and home_screen.dart's async follow-up
 * check (~75s more, only while Home is actually open) together cover most
 * cases, but if fulfillment takes even longer AND the user has since
 * closed the app entirely, neither of those can ever fire -- there's
 * nothing left running client-side to notice the eventual success. A push
 * notification is the only thing that can reach a closed app.
 *
 * The Firebase Admin SDK (FirebaseApp) is already initialized elsewhere
 * (see FirebaseConfig.kt) -- FirebaseMessaging.getInstance() just works,
 * no separate setup needed.
 */
@Service
class PushNotificationService {

    private val log = LoggerFactory.getLogger(javaClass)

    /**
     * Fire-and-forget by design: a push failure (invalid/expired token,
     * FCM outage, whatever) must NEVER affect the recharge confirmation
     * itself, which has already fully succeeded by the time this is
     * called. Callers should not propagate exceptions from here -- this
     * function already catches everything and just logs.
     */
    suspend fun sendRechargeSuccessPush(
        fcmToken: String?,
        orderId: String,
        amountRupees: BigDecimal,
        earnedCoins: Int,
        earnedValueRupees: BigDecimal
    ) {
        if (fcmToken.isNullOrBlank()) {
            log.info("Push skipped for orderId={} -- no fcm_token on file for this user", orderId)
            return
        }

        try {
            val message = Message.builder()
                .setToken(fcmToken)
                .setNotification(
                    Notification.builder()
                        .setTitle("Recharge confirmed")
                        .setBody("Your ₹$amountRupees recharge went through — tap to see your reward")
                        .build()
                )
                // Data payload -- Flutter reads this on notification-tap
                // (and on a foreground message while the app is already
                // open) to play the SAME gold coin animation the
                // synchronous/async paths use, with the real numbers,
                // no extra API round-trip needed to figure out what was
                // earned.
                .putData("type", "recharge_success")
                .putData("orderId", orderId)
                .putData("amountRupees", amountRupees.toPlainString())
                .putData("earnedCoins", earnedCoins.toString())
                .putData("earnedValueRupees", earnedValueRupees.toPlainString())
                .build()

            // Firebase Admin SDK's send() is a blocking call -- must not
            // run on a coroutine dispatcher meant for non-blocking work.
            withContext(Dispatchers.IO) {
                FirebaseMessaging.getInstance().send(message)
            }
            log.info("Push sent for orderId={}", orderId)
        } catch (e: Exception) {
            // Deliberately swallowed -- see fun-level doc comment above.
            // A stale/invalid token (user reinstalled, uninstalled, etc.)
            // is the single most common failure here and is completely
            // expected; not worth surfacing as a real error.
            log.warn("Push send failed for orderId={} (non-fatal): {}", orderId, e.message)
        }
    }
}