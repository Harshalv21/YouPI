package `in`.youpi.core

import java.time.Instant

/**
 * Abstract base for all application exceptions.
 * Every module defines its own sealed hierarchy extending this.
 * GlobalExceptionHandler maps these to HTTP status codes.
 *
 * NOTE: Must be `abstract` (not `sealed`) — Kotlin does not allow sealed classes
 * to be subclassed from a different Gradle compile module.
 */
abstract class BaseException(
    open val code: String,
    override val message: String,
    override val cause: Throwable? = null
) : RuntimeException(message, cause) {

    /** HTTP status code to return — override in subclasses */
    open val httpStatus: Int = 500
}

// ── System-level exceptions (shared across all modules) ──

class NotFoundException(
    val resource: String,
    val id: String
) : BaseException(
    code = "NOT_FOUND",
    message = "$resource with id '$id' not found"
) {
    override val httpStatus: Int = 404
}

class ForbiddenException(
    override val message: String = "Access denied"
) : BaseException(code = "FORBIDDEN", message = message) {
    override val httpStatus: Int = 403
}

class UnauthorizedException(
    override val message: String = "Authentication required"
) : BaseException(code = "UNAUTHORIZED", message = message) {
    override val httpStatus: Int = 401
}

class RateLimitExceededException(
    val retryAfterSeconds: Long
) : BaseException(
    code = "RATE_LIMITED",
    message = "Rate limit exceeded. Retry after $retryAfterSeconds seconds."
) {
    override val httpStatus: Int = 429
}

class ValidationException(
    val field: String,
    override val message: String
) : BaseException(code = "VALIDATION_ERROR", message = message) {
    override val httpStatus: Int = 400
}

class ConflictException(
    override val message: String
) : BaseException(code = "CONFLICT", message = message) {
    override val httpStatus: Int = 409
}

class IdempotencyConflictException(
    val existingId: String
) : BaseException(
    code = "IDEMPOTENCY_CONFLICT",
    message = "Request already processed with id: $existingId"
) {
    override val httpStatus: Int = 200
}

class InternalException(
    override val message: String = "Internal server error",
    override val cause: Throwable? = null
) : BaseException(code = "INTERNAL_ERROR", message = message, cause = cause) {
    override val httpStatus: Int = 500
}

class ExternalServiceException(
    val serviceName: String,
    override val message: String,
    override val cause: Throwable? = null
) : BaseException(
    code = "EXTERNAL_SERVICE_ERROR",
    message = "$serviceName: $message",
    cause = cause
) {
    override val httpStatus: Int = 502
}
