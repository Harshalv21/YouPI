package `in`.youpi.core

import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
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
 *
 * CORS safety net: CorsWebFilter normally stamps Access-Control-Allow-Origin on every
 * response, but error responses built here go through AbstractErrorWebExceptionHandler's
 * own routing function -- on some Spring Boot/WebFlux versions that path can commit the
 * response before the filter's headers are guaranteed to stick. Symptom if this happens:
 * the request succeeds server-side (you'll see a clean 401/400/500 in Cloud Run logs) but
 * the browser reports a generic "Failed to fetch" because it refuses to hand the response
 * to JS without a matching CORS header. So we re-stamp the header here explicitly, matched
 * against the same allow-list CorsConfig uses, as a belt-and-braces guarantee.
 */
@Component
@Order(-2) // Execute before default Spring error handler
class GlobalExceptionHandler(
    errorAttributes: ErrorAttributes,
    applicationContext: ApplicationContext,
    serverCodecConfigurer: ServerCodecConfigurer,
    @Value("\${youpi.cors.allowed-origins:http://localhost:8082}")
    private val allowedOriginsRaw: String
) : AbstractErrorWebExceptionHandler(
    errorAttributes, WebProperties.Resources(), applicationContext
) {

    private val log = LoggerFactory.getLogger(javaClass)

    private val allowedOrigins: List<String> by lazy {
        allowedOriginsRaw.split(",").map { it.trim() }.filter { it.isNotBlank() }
    }

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
                    request = request,
                    status = HttpStatus.valueOf(throwable.httpStatus),
                    body = ApiResponse.fromException(throwable, requestId),
                    retryAfter = if (throwable is RateLimitExceededException) throwable.retryAfterSeconds else null
                )
            }
            is org.springframework.web.server.ServerWebInputException -> {
                // throwable.message is Spring's generic wrapper text (always
                // "400 BAD_REQUEST \"Failed to read HTTP message\""), not the
                // actual reason. The real cause (e.g. the specific Jackson
                // parse error) is one level down in .cause -- log that too,
                // and pass `throwable` itself so the stack trace shows up.
                val rootCause = throwable.cause?.message ?: throwable.message
                log.warn("Validation error: {} (requestId={})", rootCause, requestId, throwable)
                buildResponse(
                    request = request,
                    status = HttpStatus.BAD_REQUEST,
                    body = ApiResponse.error("VALIDATION_ERROR", rootCause ?: "Invalid input", requestId = requestId)
                )
            }
            else -> {
                // Full detail sirf server-side log mein — client ko generic message hi jaata hai
                log.error(
                    "Unhandled exception (requestId={}): {} ({})",
                    requestId, throwable.message, throwable.javaClass.name, throwable
                )
                buildResponse(
                    request = request,
                    status = HttpStatus.INTERNAL_SERVER_ERROR,
                    body = ApiResponse.error(
                        "INTERNAL_ERROR",
                        "Something went wrong. Please try again.",
                        requestId = requestId
                    )
                )
            }
        }
    }

    private fun buildResponse(
        request: ServerRequest,
        status: HttpStatus,
        body: ApiResponse<*>,
        retryAfter: Long? = null
    ): Mono<ServerResponse> {
        val builder = ServerResponse.status(status)
            .contentType(MediaType.APPLICATION_JSON)

        if (retryAfter != null) {
            builder.header("Retry-After", retryAfter.toString())
        }

        // CORS safety net -- see class doc. Only stamps the header if the request's
        // Origin is actually on our allow-list, same rule CorsConfig enforces.
        val origin = request.headers().firstHeader("Origin")
        if (origin != null && allowedOrigins.contains(origin)) {
            builder.header("Access-Control-Allow-Origin", origin)
            builder.header("Access-Control-Allow-Credentials", "true")
        }

        return builder.body(BodyInserters.fromValue(body))
    }
}