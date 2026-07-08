plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.dependency.management)
}

dependencies {
    api(project(":shared:core"))
    implementation(libs.spring.boot.starter.test)
    implementation(libs.spring.boot.starter.webflux)
    implementation(libs.spring.boot.starter.data.r2dbc)
    implementation(libs.r2dbc.postgresql)
    implementation(libs.postgresql.jdbc)
    implementation(libs.flyway.core)
    implementation(libs.flyway.database.postgresql)
    api(libs.testcontainers.postgresql)
    api(libs.testcontainers.r2dbc)
    api(libs.testcontainers.junit.jupiter)
    api(libs.mockk)
    api(libs.kotest.runner.junit5)
    api(libs.kotest.assertions.core)
    api(libs.wiremock)
    api(libs.kotlinx.coroutines.test)
}
