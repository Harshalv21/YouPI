package `in`.youpi.core

import org.slf4j.LoggerFactory
import org.springframework.boot.autoconfigure.web.WebProperties
import org.springframework.boot.autoconfigure.web.reactive.error.AbstractErrorWebExceptionHandler
import org.springframework.boot.web.reactive.error.ErrorAttributes
import org.springframework.context.ApplicationContext
import org.springframework.core.annotation.Order
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.codec.ServerCodecConfigurer
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.BodyInserters
import org.springframework.web.reactive.function.server.*
import reactor.core.publisher.Mono

/**
 * Global exception handler that maps all BaseException subtypes to proper HTTP responses.
 * Every sealed exception returns a consistent ApiResponse with correct status code.
 * Uncaught exceptions return 500 and are reported to GCP Error Reporting.
 */
@Component
@Order(-2) // Execute before default Spring error handler
class GlobalExceptionHandler(
    errorAttributes: ErrorAttributes,
    applicationContext: ApplicationContext,
    serverCodecConfigurer: ServerCodecConfigurer
) : AbstractErrorWebExceptionHandler(
    errorAttributes, WebProperties.Resources(), applicationContext
) {

    private val log = LoggerFactory.getLogger(javaClass)

    init {
        super.setMessageWriters(serverCodecConfigurer.writers)
        super.setMessageReaders(serverCodecConfigurer.readers)
    }

    override fun getRoutingFunction(errorAttributes: ErrorAttributes): RouterFunction<ServerResponse> =
        RouterFunctions.route(RequestPredicates.all()) { request ->
            handleError(request)
        }

    private fun handleError(request: ServerRequest): Mono<ServerResponse> {
        val throwable = getError(request)
        // Try to get requestId from attributes (set by RequestIdFilter) or header
        val requestId = request.attribute("requestId").map { it.toString() }.orElseGet {
            request.headers().firstHeader("X-Request-ID") ?: "unknown"
        }

        return when (throwable) {
            is BaseException -> {
                log.warn("Business exception [{}]: {} (requestId={})", throwable.code, throwable.message, requestId)
                buildResponse(
                    status = HttpStatus.valueOf(throwable.httpStatus),
                    body = ApiResponse.fromException(throwable, requestId),
                    retryAfter = if (throwable is RateLimitExceededException) throwable.retryAfterSeconds else null
                )
            }
            is org.springframework.web.server.ServerWebInputException -> {
                log.warn("Validation error: {} (requestId={})", throwable.message, requestId)
                buildResponse(
                    status = HttpStatus.BAD_REQUEST,
                    body = ApiResponse.error("VALIDATION_ERROR", throwable.message ?: "Invalid input", requestId = requestId)
                )
            }
            else -> {
                val errorMessage = "An unexpected error occurred: ${throwable.message} (${throwable.javaClass.name})"
                log.error("Unhandled exception (requestId={}): {}", requestId, errorMessage, throwable)
                buildResponse(
                    status = HttpStatus.INTERNAL_SERVER_ERROR,
                    body = ApiResponse.error("INTERNAL_ERROR", errorMessage, requestId = requestId)
                )
            }
        }
    }

    private fun buildResponse(
        status: HttpStatus,
        body: ApiResponse<*>,
        retryAfter: Long? = null
    ): Mono<ServerResponse> {
        val builder = ServerResponse.status(status)
            .contentType(MediaType.APPLICATION_JSON)

        if (retryAfter != null) {
            builder.header("Retry-After", retryAfter.toString())
        }

        return builder.body(BodyInserters.fromValue(body))
    }
}
