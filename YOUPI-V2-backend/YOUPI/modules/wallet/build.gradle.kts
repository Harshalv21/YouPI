plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.dependency.management)
}

dependencies {
    api(project(":shared:core"))
    api(project(":shared:security")) // Added for currentUserId()
    api(project(":shared:events"))
    implementation(libs.spring.boot.starter.webflux)
    implementation(libs.spring.boot.starter.data.r2dbc)
    implementation(libs.spring.boot.starter.data.redis.reactive)

    testImplementation(project(":shared:testkit"))
    testImplementation(libs.spring.boot.starter.test)
}
