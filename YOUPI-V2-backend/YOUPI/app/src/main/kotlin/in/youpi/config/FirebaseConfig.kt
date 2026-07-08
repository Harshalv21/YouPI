package `in`.youpi.config

import com.google.auth.oauth2.GoogleCredentials
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import jakarta.annotation.PostConstruct

/**
 * Firebase initialization using Google Application Default Credentials (ADC).
 *
 * On GCP (Compute Engine / Cloud Run) the VM's attached service account is
 * automatically discovered — no JSON key file required or allowed.
 *
 * ADC resolution order:
 *  1. GOOGLE_APPLICATION_CREDENTIALS env var (path to a key file, for local dev only)
 *  2. gcloud CLI credentials  (local dev: `gcloud auth application-default login`)
 *  3. GCE / GKE metadata server  ← used automatically on Compute Engine (production)
 *  4. Cloud Run / App Engine built-in service account
 */
@Configuration
class FirebaseConfig {

    private val log = LoggerFactory.getLogger(javaClass)

    @Value("\${youpi.firebase.project-id}")
    private lateinit var projectId: String

    @Value("\${youpi.firebase.database-url:}")
    private var databaseUrl: String = ""

    @PostConstruct
    fun initFirebase() {
        // Guard: Firebase SDK throws if you initialise the default app twice
        if (FirebaseApp.getApps().isNotEmpty()) {
            log.info("FirebaseApp already initialised — skipping.")
            return
        }

        try {
            // ── Application Default Credentials ──────────────────────────────
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
            log.warn("Firebase initialization skipped or failed. On GCE ensure the VM has a service account attached with the 'Firebase Admin SDK Service Agent' role. Error: {}", e.message)
        }
    }
}
