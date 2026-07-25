package `in`.youpi.config

import com.google.auth.oauth2.GoogleCredentials
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.core.env.Environment
import jakarta.annotation.PostConstruct

/**
 * Firebase initialization using Google Application Default Credentials (ADC).
 * ...
 */
@Configuration
class FirebaseConfig(
    private val environment: Environment   // ← naya: active profile check karne ke liye
) {

    private val log = LoggerFactory.getLogger(javaClass)

    @Value("\${youpi.firebase.project-id}")
    private lateinit var projectId: String

    @Value("\${youpi.firebase.database-url:}")
    private var databaseUrl: String = ""

    @PostConstruct
    fun initFirebase() {
        if (FirebaseApp.getApps().isNotEmpty()) {
            log.info("FirebaseApp already initialised — skipping.")
            return
        }

        try {
            val options = FirebaseOptions.builder()
                .setCredentials(GoogleCredentials.getApplicationDefault())
                .setProjectId(projectId)

            if (databaseUrl.isNotBlank()) {
                options.setDatabaseUrl(databaseUrl)
            }

            if (FirebaseApp.getApps().isEmpty()) {
                FirebaseApp.initializeApp(options.build())
                log.info("Firebase initialized for project: {}", projectId)
            } else {
                log.info("Firebase already initialized")
            }
        } catch (e: Exception) {
            val activeProfiles = environment.activeProfiles.toList()
            val isProd = activeProfiles.any { it == "gcp" || it == "prod" }

            if (isProd) {
                log.error("Firebase initialization FAILED in profile(s) {} — refusing to start", activeProfiles, e)
                throw IllegalStateException("Firebase init failed in production profile — cannot start app", e)
            }
            log.warn("Firebase initialization skipped/failed (non-prod profile {}) — continuing", activeProfiles, e)
        }
    }
}
