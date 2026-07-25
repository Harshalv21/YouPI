package `in`.youpi.security

import org.springframework.beans.factory.annotation.Value
import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.util.AntPathMatcher
import org.springframework.web.server.ServerWebExchange
import org.springframework.web.server.WebFilter
import org.springframework.web.server.WebFilterChain
import reactor.core.publisher.Mono

/**
 * Blocks every endpoint belonging to a module that isn't part of this
 * version's launch scope, no matter how the request arrives (app UI,
 * Postman, curl, a stale APK). This is server-side enforcement --
 * it does NOT rely on the Flutter app hiding the "Coming Soon" screens.
 *
 * Runs early (right after PathNormalizingFilter), before auth/rate-limit
 * checks, so disabled modules don't waste a Redis round trip or a
 * token-verification call.
 *
 * Skip-list style mirrors FirebaseAuthFilter: both "/v1/..." and
 * "/api/v1/..." are matched because it's not confirmed at this layer
 * whether the LB/ingress in front of Cloud Run strips an "/api" prefix
 * in every environment.
 *
 * NOTE: modules/invest exposes gold-buy/sell/FD endpoints under the
 * SAME "/v1/gold/..." prefix as modules/gold's reward wallet. Only
 * GET /v1/gold/wallet (view gold-gram balance -- no wallet dependency)
 * is left OUT of any gated list, so the Gold Reward display (tied to
 * Recharge) keeps working. POST /v1/gold/withdraw is gated behind
 * wallet-enabled instead of invest-enabled, since it internally credits
 * WalletService and there'd be nowhere to see that cash with wallet off.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
class FeatureGateFilter(
    @Value("\${youpi.features.wallet-enabled:false}") private val walletEnabled: Boolean,
    @Value("\${youpi.features.invest-enabled:false}") private val investEnabled: Boolean,
    @Value("\${youpi.features.loan-enabled:false}") private val loanEnabled: Boolean,
    @Value("\${youpi.features.bnpl-enabled:false}") private val bnplEnabled: Boolean,
    @Value("\${youpi.features.smart-saver-enabled:false}") private val smartSaverEnabled: Boolean,
    @Value("\${youpi.features.kyc-enabled:false}") private val kycEnabled: Boolean,
) : WebFilter {

    private val matcher = AntPathMatcher()

    private data class Rule(val patterns: List<String>, val enabled: () -> Boolean, val feature: String)

    // First matching rule wins. Order matters: more specific gold/invest
    // paths must be checked before any accidental broader gold pattern.
    private val rules: List<Rule> by lazy {
        listOf(
            Rule(listOf("/v1/wallet/**", "/api/v1/wallet/**"), { walletEnabled }, "wallet"),
            // Gold withdraw internally credits WalletService (see GoldWithdrawService) --
            // with the wallet module off, withdrawal has nowhere visible for the credited
            // cash to land, so it's gated off too. GET /v1/gold/wallet (view gold-gram
            // balance) has no wallet dependency and stays live.
            Rule(listOf("/v1/gold/withdraw", "/api/v1/gold/withdraw"), { walletEnabled }, "gold-withdraw"),
            Rule(listOf("/v1/loan/**", "/api/v1/loan/**"), { loanEnabled }, "loan"),
            Rule(listOf("/v1/bnpl/**", "/api/v1/bnpl/**"), { bnplEnabled }, "bnpl"),
            Rule(listOf("/v1/smart-saver/**", "/api/v1/smart-saver/**"), { smartSaverEnabled }, "smart-saver"),
            Rule(
                listOf(
                    "/v1/gold/price", "/api/v1/gold/price",
                    "/v1/gold/holdings", "/api/v1/gold/holdings",
                    "/v1/gold/buy", "/api/v1/gold/buy",
                    "/v1/gold/sell", "/api/v1/gold/sell",
                    "/v1/gold/passbook", "/api/v1/gold/passbook",
                    "/v1/gold/history", "/api/v1/gold/history",
                    "/v1/gold/products", "/api/v1/gold/products",
                    "/v1/gold/transactions", "/api/v1/gold/transactions",
                    "/v1/gold/kyc", "/api/v1/gold/kyc",
                    "/v1/gold/user", "/api/v1/gold/user",
                    "/v1/fd/**", "/api/v1/fd/**",
                ),
                { investEnabled },
                "invest",
            ),
            Rule(listOf("/v1/user/kyc/**", "/api/v1/user/kyc/**"), { kycEnabled }, "kyc"),
        )
    }

    override fun filter(exchange: ServerWebExchange, chain: WebFilterChain): Mono<Void> {
        val method = exchange.request.method
        if (method?.name() == "OPTIONS") {
            return chain.filter(exchange)
        }

        val path = exchange.request.uri.path.replace(Regex("/+"), "/")

        val rule = rules.firstOrNull { r -> r.patterns.any { matcher.match(it, path) } }
        if (rule != null && !rule.enabled()) {
            return writeFeatureDisabled(exchange, rule.feature)
        }

        return chain.filter(exchange)
    }

    private fun writeFeatureDisabled(exchange: ServerWebExchange, feature: String): Mono<Void> {
        exchange.response.statusCode = HttpStatus.FORBIDDEN
        exchange.response.headers.set("Content-Type", "application/json")
        val body = """{"success":false,"error":{"code":"FEATURE_DISABLED","message":"This feature ($feature) is coming soon and isn't available in this version."}}"""
        val buffer = exchange.response.bufferFactory().wrap(body.toByteArray())
        return exchange.response.writeWith(Mono.just(buffer))
    }
}