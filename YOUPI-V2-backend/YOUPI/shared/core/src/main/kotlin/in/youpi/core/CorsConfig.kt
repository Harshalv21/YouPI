package `in`.youpi.core

import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.web.cors.CorsConfiguration
import org.springframework.web.cors.reactive.CorsWebFilter
import org.springframework.web.cors.reactive.UrlBasedCorsConfigurationSource

@Configuration
class CorsConfig(
    @Value("\${youpi.cors.allowed-origins:http://localhost:8082}")
    private val allowedOriginsRaw: String
) {

    @Bean
    fun corsWebFilter(): CorsWebFilter {
        val config = CorsConfiguration()

        // Comma-separated list env var se, e.g.: YOUPI_CORS_ALLOWED_ORIGINS=https://admin.youpi.in,https://youpi.in
        config.allowedOrigins = allowedOriginsRaw.split(",").map { it.trim() }.filter { it.isNotBlank() }

        config.allowedMethods = listOf("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS")
        config.allowedHeaders = listOf("*")
        config.allowCredentials = true
        config.maxAge = 3600

        val source = UrlBasedCorsConfigurationSource()
        source.registerCorsConfiguration("/**", config)

        return CorsWebFilter(source)
    }
}