package `in`.youpi.core

import com.fasterxml.jackson.annotation.JsonInclude

/**
 * Cursor-based paginated response for all list endpoints.
 * Cursor pagination is preferred over offset-based for fintech ledger queries.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
data class PaginatedResponse<T>(
    val items: List<T>,
    val totalCount: Long? = null,
    val cursor: String? = null,
    val hasMore: Boolean = false,
    val pageSize: Int
) {
    companion object {
        fun <T> of(items: List<T>, pageSize: Int, totalCount: Long? = null, cursor: String? = null): PaginatedResponse<T> =
            PaginatedResponse(
                items = items,
                totalCount = totalCount,
                cursor = cursor,
                hasMore = items.size >= pageSize,
                pageSize = pageSize
            )

        fun <T> empty(pageSize: Int): PaginatedResponse<T> = PaginatedResponse(
            items = emptyList(),
            totalCount = 0,
            cursor = null,
            hasMore = false,
            pageSize = pageSize
        )
    }
}
