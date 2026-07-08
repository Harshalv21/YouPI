package `in`.youpi.core

/**
 * Sealed result type for all service returns.
 * Forces callers to handle both success and error cases explicitly.
 * NEVER return nullable from services — use this instead.
 */
sealed class Result<out T, out E> {

    data class Success<out T>(val value: T) : Result<T, Nothing>()
    data class Failure<out E>(val error: E) : Result<Nothing, E>()

    val isSuccess: Boolean get() = this is Success
    val isFailure: Boolean get() = this is Failure

    fun getOrNull(): T? = when (this) {
        is Success -> value
        is Failure -> null
    }

    fun errorOrNull(): E? = when (this) {
        is Success -> null
        is Failure -> error
    }

    inline fun <R> map(transform: (T) -> R): Result<R, E> = when (this) {
        is Success -> Success(transform(value))
        is Failure -> this
    }

    inline fun <R> mapError(transform: (E) -> R): Result<T, R> = when (this) {
        is Success -> this
        is Failure -> Failure(transform(error))
    }

    inline fun <R> flatMap(transform: (T) -> Result<R, @UnsafeVariance E>): Result<R, E> = when (this) {
        is Success -> transform(value)
        is Failure -> this
    }

    inline fun onSuccess(action: (T) -> Unit): Result<T, E> {
        if (this is Success) action(value)
        return this
    }

    inline fun onFailure(action: (E) -> Unit): Result<T, E> {
        if (this is Failure) action(error)
        return this
    }

    fun getOrThrow(transform: (E) -> Throwable = { IllegalStateException("Result is Failure: $it") }): T =
        when (this) {
            is Success -> value
            is Failure -> throw transform(error)
        }

    companion object {
        fun <T> success(value: T): Result<T, Nothing> = Success(value)
        fun <E> failure(error: E): Result<Nothing, E> = Failure(error)
    }
}
