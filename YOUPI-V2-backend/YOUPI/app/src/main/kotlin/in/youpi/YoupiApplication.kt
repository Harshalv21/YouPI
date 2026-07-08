package `in`.youpi

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import org.springframework.data.r2dbc.config.EnableR2dbcAuditing
import org.springframework.scheduling.annotation.EnableScheduling

/**
 * YouPI Super App — Main Application Entry Point
 *
 * Kotlin Spring Boot 3.2 · WebFlux (Reactive) · R2DBC · Coroutines
 * Nexospendz Finothrive Pvt. Ltd.
 */
@SpringBootApplication(scanBasePackages = ["in.youpi"])
@EnableR2dbcAuditing
@EnableScheduling
class YoupiApplication

fun main(args: Array<String>) {
    runApplication<YoupiApplication>(*args)
}
