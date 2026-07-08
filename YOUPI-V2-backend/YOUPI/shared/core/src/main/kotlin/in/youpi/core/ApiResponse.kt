package `in`.youpi.core

import com.fasterxml.jackson.annotation.JsonInclude
import java.time.Instant
import java.util.UUID

/**
 * Canonical API response envelope for all endpoints.
 * Every response from YouPI follows this structure:
 *   { success: true/false, data: T, error: ErrorInfo?, requestId: UUID, timestamp: Instant }
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
data class ApiResponse<T>(
    val success: Boolean,
    val data: T? = null,
    val error: ErrorInfo? = null,
    val requestId: String = UUID.randomUUID().toString(),
    val timestamp: Instant = Instant.now()
) {
    companion object {
        fun <T> ok(data: T, requestId: String? = null): ApiResponse<T> = ApiResponse(
            success = true,
            data = data,
            requestId = requestId ?: UUID.randomUUID().toString()
        )

        fun <T> created(data: T, requestId: String? = null): ApiResponse<T> = ok(data, requestId)

        fun error(
            code: String,
            message: String,
            details: Map<String, Any>? = null,
            requestId: String? = null
        ): ApiResponse<Nothing> = ApiResponse(
            success = false,
            error = ErrorInfo(code = code, message = message, details = details),
            requestId = requestId ?: UUID.randomUUID().toString()
        )

        fun fromException(ex: BaseException, requestId: String? = null): ApiResponse<Nothing> = ApiResponse(
            success = false,
            error = ErrorInfo(code = ex.code, message = ex.message),
            requestId = requestId ?: UUID.randomUUID().toString()
        )
    }
}

@JsonInclude(JsonInclude.Include.NON_NULL)
data class ErrorInfo(
    val code: String,
    val message: String,
    val details: Map<String, Any>? = null
)
