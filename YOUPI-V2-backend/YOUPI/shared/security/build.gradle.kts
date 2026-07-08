plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.dependency.management)
}

dependencies {
    api(project(":shared:core"))
    implementation(libs.spring.boot.starter.webflux)
    implementation(libs.spring.boot.starter.data.redis.reactive)
    implementation(libs.firebase.admin)
    implementation(libs.jjwt.api)
    implementation(libs.jjwt.impl)
    implementation(libs.jjwt.jackson)
    implementation(libs.bcrypt)
    implementation(libs.kotlinx.coroutines.reactor)

    testImplementation(libs.spring.boot.starter.test)
    testImplementation(libs.mockk)
}
