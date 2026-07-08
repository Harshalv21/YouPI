# ══════════════════════════════════════════════════════════════
# YouPI Backend — Multi-stage Docker Build
# JDK 21 · Kotlin · Spring Boot 3.2 · WebFlux · PostgreSQL
# ══════════════════════════════════════════════════════════════

# ── Stage 1: Build ──────────────────────────────────────────
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app

# Verify Java version (must be 21 to match toolchain in build.gradle.kts)
RUN java -version && javac -version

# Copy the Gradle wrapper and configuration files first
COPY gradlew ./
COPY gradle/ gradle/
COPY build.gradle.kts settings.gradle.kts ./

# Ensure gradlew is executable
RUN chmod +x ./gradlew

# Copy all module build files for dependency caching
COPY app/build.gradle.kts app/
COPY shared/core/build.gradle.kts shared/core/
COPY shared/security/build.gradle.kts shared/security/
COPY shared/events/build.gradle.kts shared/events/
COPY shared/testkit/build.gradle.kts shared/testkit/
COPY modules/auth/build.gradle.kts modules/auth/
COPY modules/user/build.gradle.kts modules/user/
COPY modules/recharge/build.gradle.kts modules/recharge/
COPY modules/payment/build.gradle.kts modules/payment/
COPY modules/wallet/build.gradle.kts modules/wallet/
COPY modules/smart-saver/build.gradle.kts modules/smart-saver/
COPY modules/invest/build.gradle.kts modules/invest/
COPY modules/bnpl/build.gradle.kts modules/bnpl/
COPY modules/loan/build.gradle.kts modules/loan/
COPY modules/admin/build.gradle.kts modules/admin/

# Pre-fetch dependencies using the wrapper
RUN ./gradlew dependencies --no-daemon --quiet 2>/dev/null || true

# Copy all source code
COPY . .

# Build the fat JAR with a fresh gradle build each time
# --no-build-cache  → ensures a fresh build
# --no-daemon       → avoids Gradle daemon issues inside Docker
# -x test           → skip tests (run them in CI separately)
RUN chmod +x ./gradlew && ./gradlew :app:bootJar --no-daemon --no-build-cache -x test

# ── Stage 2: Runtime ────────────────────────────────────────
# Use JRE (not JDK) for a smaller, more secure image
FROM eclipse-temurin:21-jre-alpine AS runtime

# Security: run as non-root
RUN addgroup -S youpi && adduser -S youpi -G youpi
WORKDIR /app

# Copy the built JAR from builder stage
COPY --from=builder /app/app/build/libs/app-*.jar app.jar

# Firebase service account (mounted at runtime via docker-compose volume)
RUN mkdir -p firebase

# JVM tuning for containerised environment
ENV JAVA_OPTS="-XX:+UseG1GC -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD wget -qO- http://localhost:8082/api/actuator/health || exit 1

USER youpi
EXPOSE 8082

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
