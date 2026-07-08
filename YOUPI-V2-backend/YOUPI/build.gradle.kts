import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.spring) apply false
    alias(libs.plugins.spring.boot) apply false
    alias(libs.plugins.spring.dependency.management) apply false
}

allprojects {
    group = "in.youpi"
    version = "1.0.0"

    repositories {
        mavenCentral()
        google()
    }
}

subprojects {
    apply(plugin = "org.jetbrains.kotlin.jvm")

    // ── Java Toolchain — pins compileJava AND compileKotlin to the same JVM ──
    // This is the ONLY correct fix for:
    //   "Inconsistent JVM-target compatibility: compileJava (21) vs compileKotlin (17)"
    extensions.configure<JavaPluginExtension> {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(21))
        }
    }

    dependencies {
        val implementation by configurations
        val testImplementation by configurations

        implementation(rootProject.libs.kotlin.stdlib)
        implementation(rootProject.libs.kotlin.reflect)
        implementation(rootProject.libs.kotlinx.coroutines.core)
        implementation(rootProject.libs.kotlinx.coroutines.reactor)
        implementation(rootProject.libs.kotlinx.coroutines.jdk8)
        implementation(rootProject.libs.jackson.module.kotlin)
        implementation(rootProject.libs.jackson.datatype.jsr310)

        testImplementation(rootProject.libs.kotlinx.coroutines.test)
        testImplementation(rootProject.libs.mockk)
        testImplementation(rootProject.libs.kotest.runner.junit5)
        testImplementation(rootProject.libs.kotest.assertions.core)
    }

    // ── Kotlin compiler options ──
    // Do NOT set jvmTarget manually here — the toolchain above handles it.
    tasks.withType<KotlinCompile> {
        kotlinOptions {
            freeCompilerArgs += "-Xjsr305=strict"
            // jvmTarget is intentionally omitted — toolchain sets it to "21"
        }
    }

    tasks.withType<Test> {
        useJUnitPlatform()
    }
}
