package `in`.youpi.core

import jakarta.validation.Validation
import jakarta.validation.Validator
import org.springframework.web.reactive.function.server.ServerRequest
import org.springframework.web.reactive.function.server.awaitBody

/**
 * Bridges jakarta.validation (Bean Validation) into this app's functional
 * `coRouter` handlers.
 *
 * WHY THIS EXISTS: spring-boot-starter-validation is already a dependency
 * and Hibernate Validator is on the classpath, but `@Valid` only auto-fires
 * on annotated `@RestController` methods via Spring MVC/WebFlux's argument
 * resolvers. This app uses functional routing (`coRouter { POST("/x") { ... } }`)
 * everywhere instead, so `request.awaitBody<SomeRequest>()` deserializes the
 * JSON but any `@field:NotBlank` / `@field:Pattern` / etc. annotations on the
 * DTO are silently never checked. Declarative annotations on a DTO with
 * nothing reading them are worse than no annotations -- they look like
 * enforced validation in a code review but aren't.
 *
 * Use `request.awaitValidatedBody<T>()` in place of `request.awaitBody<T>()`
 * anywhere the body is a client-supplied request DTO. It deserializes, then
 * runs Bean Validation, then throws the existing `ValidationException`
 * (already mapped to 400 VALIDATION_ERROR by GlobalExceptionHandler) on the
 * first constraint violation -- so no new exception-handling wiring is
 * needed anywhere else.
 */
object RequestValidator {
    val instance: Validator by lazy {
        Validation.buildDefaultValidatorFactory().validator
    }
}

/**
 * Reads and deserializes the request body like [awaitBody], then runs
 * jakarta.validation constraints declared on [T] and throws
 * [ValidationException] (400) on the first violation, in field-name order
 * so the same input always fails on the same field.
 */
suspend inline fun <reified T : Any> ServerRequest.awaitValidatedBody(): T {
    val body = awaitBody<T>()
    val violations = RequestValidator.instance.validate(body)
    if (violations.isNotEmpty()) {
        val first = violations.minByOrNull { it.propertyPath.toString() }!!
        throw ValidationException(
            field = first.propertyPath.toString(),
            message = "${first.propertyPath}: ${first.message}"
        )
    }
    return body
}
