plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.dependency.management)
}

dependencies {
    api(libs.spring.boot.starter.webflux)
    api(libs.spring.boot.starter.validation)
    api(libs.spring.boot.starter.actuator)
    api(libs.springdoc.openapi.webflux.ui)
    api(libs.spring.boot.starter.data.redis.reactive)
    api(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.coroutines.reactor)
    api(libs.jackson.module.kotlin)
    api(libs.jackson.datatype.jsr310)
    api(libs.logstash.logback.encoder)
}
