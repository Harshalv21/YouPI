package `in`.youpi.security

import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM encryption service for PII at rest (Aadhaar, PAN).
 * Key injected from GCP Secret Manager (rotatable).
 * IV is prepended to ciphertext for decryption.
 */
@Service
class EncryptionService(
    @Value("\${youpi.encryption.aes-key:}") private val aesKeyBase64: String
) {

    private val log = LoggerFactory.getLogger(javaClass)
    private val secureRandom = SecureRandom()

    companion object {
        private const val ALGORITHM = "AES/GCM/NoPadding"
        private const val TAG_LENGTH_BITS = 128
        private const val IV_LENGTH_BYTES = 12
        private const val KEY_LENGTH_BYTES = 32  // AES-256
    }

    private val secretKey: SecretKey? by lazy {
        if (aesKeyBase64.isBlank()) {
            log.warn("AES encryption key not configured — encryption disabled")
            null
        } else {
            val keyBytes = Base64.getDecoder().decode(aesKeyBase64)
            require(keyBytes.size == KEY_LENGTH_BYTES) {
                "AES key must be exactly $KEY_LENGTH_BYTES bytes (256 bits)"
            }
            SecretKeySpec(keyBytes, "AES")
        }
    }

    /**
     * Encrypt plaintext. Returns IV (12 bytes) prepended to ciphertext.
     */
    fun encrypt(plaintext: String): ByteArray {
        val key = secretKey ?: throw IllegalStateException("Encryption key not configured")

        val iv = ByteArray(IV_LENGTH_BYTES).also { secureRandom.nextBytes(it) }
        val cipher = Cipher.getInstance(ALGORITHM)
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_LENGTH_BITS, iv))

        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))

        // Prepend IV to ciphertext
        return iv + ciphertext
    }

    /**
     * Decrypt ciphertext. Expects IV prepended (first 12 bytes).
     */
    fun decrypt(ciphertext: ByteArray): String {
        val key = secretKey ?: throw IllegalStateException("Encryption key not configured")

        require(ciphertext.size > IV_LENGTH_BYTES) { "Ciphertext too short" }

        val iv = ciphertext.copyOfRange(0, IV_LENGTH_BYTES)
        val encrypted = ciphertext.copyOfRange(IV_LENGTH_BYTES, ciphertext.size)

        val cipher = Cipher.getInstance(ALGORITHM)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_LENGTH_BITS, iv))

        return String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    /**
     * Check if encryption is available (key configured).
     */
    fun isEnabled(): Boolean = secretKey != null
}
