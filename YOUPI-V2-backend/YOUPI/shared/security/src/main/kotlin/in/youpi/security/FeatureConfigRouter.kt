package `in`.youpi.security

import `in`.youpi.core.ApiResponse
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.web.reactive.function.server.*

/**
 * Public, unauthenticated endpoint so the Flutter app can find out at
 * startup which modules are live vs "Coming Soon" WITHOUT hardcoding it
 * client-side. Source of truth is application.yml (youpi.features.*),
 * the same flags FeatureGateFilter enforces server-side.
 *
 * Must be added to FirebaseAuthFilter's skipPaths (it's called on the
 * splash screen, before login).
 */
@Configuration
class FeatureConfigRouter(
    @Value("\${youpi.features.wallet-enabled:false}") private val walletEnabled: Boolean,
    @Value("\${youpi.features.invest-enabled:false}") private val investEnabled: Boolean,
    @Value("\${youpi.features.loan-enabled:false}") private val loanEnabled: Boolean,
    @Value("\${youpi.features.bnpl-enabled:false}") private val bnplEnabled: Boolean,
    @Value("\${youpi.features.smart-saver-enabled:false}") private val smartSaverEnabled: Boolean,
    @Value("\${youpi.features.kyc-enabled:false}") private val kycEnabled: Boolean,
) {

    @Bean
    fun featureConfigRoutes() = coRouter {
        "/v1/config".nest {
            GET("/features") {
                val flags = mapOf(
                    "rechargeEnabled" to true,
                    "goldRewardEnabled" to true,
                    "goldWithdrawEnabled" to walletEnabled,
                    "walletEnabled" to walletEnabled,
                    "investEnabled" to investEnabled,
                    "loanEnabled" to loanEnabled,
                    "bnplEnabled" to bnplEnabled,
                    "smartSaverEnabled" to smartSaverEnabled,
                    "kycEnabled" to kycEnabled,
                )
                ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                    .bodyValueAndAwait(ApiResponse.ok(flags))
            }
        }
    }
}
