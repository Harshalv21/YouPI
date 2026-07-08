plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.dependency.management)
}

dependencies {
    api(project(":shared:core"))
    api(project(":shared:security"))
    api(project(":shared:events"))
    implementation(project(":modules:auth"))  // AdminService uses UserEntity + UserRepository
    implementation(libs.spring.boot.starter.webflux)
    implementation(libs.spring.boot.starter.data.r2dbc)
    implementation(libs.spring.boot.starter.data.redis.reactive)
    implementation(libs.firebase.admin)

    testImplementation(project(":shared:testkit"))
    testImplementation(libs.spring.boot.starter.test)
}
