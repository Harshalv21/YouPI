plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.dependency.management)
}

dependencies {
    api(project(":shared:core"))
    implementation(libs.firebase.admin)
    implementation(libs.google.cloud.pubsub)
    implementation(libs.kotlinx.coroutines.jdk8)
}
