package `in`.youpi.app.config

import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.context.annotation.Primary
import org.springframework.http.client.reactive.ReactorClientHttpConnector
import org.springframework.web.reactive.function.client.WebClient
import reactor.netty.http.client.HttpClient
import reactor.netty.transport.ProxyProvider
import java.time.Duration

@Configuration
class WebClientConfig(
    @Value("\${youpi.proxy.enabled:true}") private val proxyEnabled: Boolean,
    @Value("\${youpi.proxy.host:10.160.0.2}") private val proxyHost: String,
    @Value("\${youpi.proxy.port:3128}") private val proxyPort: Int
) {
    private val log = LoggerFactory.getLogger(javaClass)

    // UNCHANGED default bean -- @Primary so every EXISTING injection point
    // (e.g. Razorpay.kt) keeps resolving to this one automatically, with NO
    // proxy. Razorpay doesn't do IP-whitelisting, so routing its traffic
    // through the proxy VM would be pure unnecessary risk -- it would make
    // payment order creation depend on the proxy VM's uptime too, which is
    // far more critical than recharge-plan browsing. Don't couple them.
    @Primary
    @Bean
    fun webClient(): WebClient = WebClient.builder()
        .clientConnector(
            ReactorClientHttpConnector(
                HttpClient.create()
                    .responseTimeout(Duration.ofSeconds(10))
                    .compress(true)
            )
        )
        .codecs { it.defaultCodecs().maxInMemorySize(1 * 1024 * 1024) }
        .build()

    // Separate, explicitly-qualified bean -- ONLY for calls to vendors that
    // enforce IP whitelisting (currently: mPlan, via RechargeService).
    // Routes through the proxy VM (Squid on 10.160.0.2:3128), which has a
    // genuinely fixed IP -- unlike Cloud Run's own outbound IP, confirmed
    // unstable via diagnostic logging across three separate VPC-egress
    // configurations. That instability is what caused mPlan's
    // "You are not authorize." IP-whitelist rejections.
    //
    // Toggleable via config (default ON) so it can be flipped off quickly
    // without a redeploy if the proxy VM is ever down for maintenance --
    // in that case vendor calls go direct instead of failing outright
    // (though then they'll hit the IP-whitelist issue again).
    @Bean("proxiedWebClient")
    @Qualifier("proxiedWebClient")
    fun proxiedWebClient(): WebClient {
        val httpClient = HttpClient.create()
            .responseTimeout(Duration.ofSeconds(10))
            .compress(true)
            // Explicitly HTTP/1.1 -- curl defaults to HTTP/1.1, but Java/
            // Reactor Netty clients can attempt HTTP/2 (ALPN) negotiation by
            // default. mPlan's server (or a WAF in front of it) may be
            // filtering based on that difference, since curl consistently
            // succeeds from this same IP while our backend consistently
            // fails -- forcing HTTP/1.1 rules this out as a cause.
            .protocol(reactor.netty.http.HttpProtocol.HTTP11)
            .let { client ->
                if (proxyEnabled) {
                    log.info("proxiedWebClient: routing via proxy {}:{}", proxyHost, proxyPort)
                    client.proxy { proxySpec ->
                        proxySpec.type(ProxyProvider.Proxy.HTTP)
                            .host(proxyHost)
                            .port(proxyPort)
                    }
                } else {
                    log.warn("proxiedWebClient: proxy DISABLED -- vendor calls will use Cloud Run's " +
                            "own (unstable) IP. Only intended as a temporary fallback.")
                    client
                }
            }

        return WebClient.builder()
            .clientConnector(ReactorClientHttpConnector(httpClient))
            .codecs { it.defaultCodecs().maxInMemorySize(1 * 1024 * 1024) }
            .build()
    }
}