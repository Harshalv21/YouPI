package `in`.youpi.smartsaver.api

import `in`.youpi.core.ApiResponse
import `in`.youpi.core.Result
import `in`.youpi.security.currentUserId
import `in`.youpi.smartsaver.service.SmartSaverService
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.responses.ApiResponse as SwaggerApiResponse
import org.springdoc.core.annotations.RouterOperation
import org.springdoc.core.annotations.RouterOperations
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.RequestMethod
import org.springframework.web.reactive.function.server.*
import java.math.BigDecimal

@Configuration
class SmartSaverRouter(private val service: SmartSaverService) {

    @Bean
    @RouterOperations(
        RouterOperation(path = "/v1/smart-saver/balance", method = [RequestMethod.GET],
            operation = Operation(operationId = "getSmartSaverBalance", summary = "Get Smart Saver balance",
                description = "Returns the Smart Saver allocation: deposit, collateral, credit limit, used/available credit.",
                tags = ["Smart Saver"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Smart Saver allocation details")])),
        RouterOperation(path = "/v1/smart-saver/deposit", method = [RequestMethod.POST],
            operation = Operation(operationId = "addSmartSaverDeposit", summary = "Add deposit",
                description = "Adds a deposit amount to the Smart Saver allocation, increasing the credit limit by 80%.",
                tags = ["Smart Saver"],
                responses = [SwaggerApiResponse(responseCode = "200", description = "Deposit added, new allocation returned")]))
    )
    fun smartSaverRoutes() = coRouter {
        "/v1/smart-saver".nest {
            GET("/balance") { handleGetBalance(it) }
            POST("/deposit") { handleDeposit(it) }
        }
    }

    private suspend fun handleGetBalance(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val balance = service.getAllocation(userId)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(balance))
    }

    private suspend fun handleDeposit(request: ServerRequest): ServerResponse {
        val userId = request.currentUserId()
        val body = request.awaitBody<Map<String, Any>>()
        val amount = BigDecimal(body["amount"].toString())
        val result = service.addDeposit(userId, amount)
        return ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
            .bodyValueAndAwait(ApiResponse.ok(result))
    }
}
