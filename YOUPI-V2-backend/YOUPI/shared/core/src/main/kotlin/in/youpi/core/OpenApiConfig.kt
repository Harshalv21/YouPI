package `in`.youpi.core

import io.swagger.v3.oas.models.Components
import io.swagger.v3.oas.models.OpenAPI
import io.swagger.v3.oas.models.info.Info
import io.swagger.v3.oas.models.security.SecurityRequirement
import io.swagger.v3.oas.models.security.SecurityScheme
import io.swagger.v3.oas.models.tags.Tag
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration

/**
 * Central OpenAPI 3.0 configuration — powers Swagger UI at /swagger-ui.html
 */
@Configuration
class OpenApiConfig {

    @Bean
    fun youpiOpenApi(): OpenAPI {
        return OpenAPI()
            .info(
                Info()
                    .title("YouPI V2 API")
                    .version("2.0.0")
            )
            .servers(
                listOf(
                    io.swagger.v3.oas.models.servers.Server().url("/api").description("Relative to current host (recommended default)"),
                    io.swagger.v3.oas.models.servers.Server().url("https://youpi-api-887162129478.asia-south1.run.app/api").description("Production (Cloud Run)"),
                    io.swagger.v3.oas.models.servers.Server().url("http://localhost:8082/api").description("Local HTTP")
                )
            )
            .components(
                Components()
                    .addSecuritySchemes(
                        "bearerAuth",
                        SecurityScheme()
                            .type(SecurityScheme.Type.HTTP)
                            .scheme("bearer")
                            .bearerFormat("JWT")
                            .description("MPIN JWT token from /api/v1/auth/mpin/verify")
                    )
                    .addSecuritySchemes(
                        "firebaseAuth",
                        SecurityScheme()
                            .type(SecurityScheme.Type.HTTP)
                            .scheme("bearer")
                            .bearerFormat("Firebase ID Token")
                            .description("Firebase Auth ID token for user identification")
                    )
            )
            .addSecurityItem(SecurityRequirement().addList("bearerAuth"))
            .tags(
                listOf(
                    Tag().name("Auth").description("OTP login, MPIN setup/verify, token management"),
                    Tag().name("User").description("User profile & KYC management"),
                    Tag().name("Recharge").description("Mobile recharge plans, orders, EMI"),
                    Tag().name("Payment").description("Razorpay payment orders & webhooks"),
                    Tag().name("Smart Saver").description("Deposit-backed credit facility"),
                    Tag().name("Gold").description("Digital gold buy/sell & holdings"),
                    Tag().name("Fixed Deposit").description("FD listing & management"),
                    Tag().name("BNPL").description("Buy Now Pay Later application & accounts"),
                    Tag().name("Loan").description("Personal loan application, EMI schedule"),
                    Tag().name("Wallet").description("NBFC wallet, P2P transfer, ledger"),
                    Tag().name("Admin").description("Admin dashboard, user management")
                )
            )
    }
}