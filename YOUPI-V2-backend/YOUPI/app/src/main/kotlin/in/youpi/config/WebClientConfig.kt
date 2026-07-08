package `in`.youpi.app.config

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.client.reactive.ReactorClientHttpConnector
import org.springframework.web.reactive.function.client.WebClient
import reactor.netty.http.client.HttpClient
import java.time.Duration

@Configuration
class WebClientConfig {

    @Bean
    fun webClient(): WebClient = WebClient.builder()
        .clientConnector(
            ReactorClientHttpConnector(
                HttpClient.create()
                    .responseTimeout(Duration.ofSeconds(10))   // 10s timeout
                    .compress(true)
            )
        )
        .codecs { it.defaultCodecs().maxInMemorySize(1 * 1024 * 1024) }  // 1MB
        .build()
}