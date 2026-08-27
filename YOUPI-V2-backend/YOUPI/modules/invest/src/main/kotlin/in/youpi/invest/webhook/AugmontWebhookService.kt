package `in`.youpi.invest.webhook

import `in`.youpi.invest.service.AugmontUserMappingRepository
import `in`.youpi.invest.service.GoldTransactionRepository
import com.fasterxml.jackson.databind.ObjectMapper
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.data.annotation.Id
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.stereotype.Service
import org.springframework.web.reactive.function.server.ServerRequest
import org.springframework.web.reactive.function.server.ServerResponse
import org.springframework.web.reactive.function.server.awaitBody
import org.springframework.web.reactive.function.server.bodyValueAndAwait
import org.springframework.web.reactive.function.server.coRouter
import java.time.Instant
import java.util.UUID

// ── Audit log entity ──

@Table("augmont_webhook_events")
data class AugmontWebhookEventEntity(
    @Id val id: UUID? = null,
    val eventType: String,
    val status: String? = null,
    val uniqueId: String? = null,
    val transactionId: String? = null,
    val merchantTransactionId: String? = null,
    val matchedLocalRecord: Boolean = false,
    val rawPayload: String,
    val receivedAt: Instant = Instant.now()
)

interface AugmontWebhookEventRepository : CoroutineCrudRepository<AugmontWebhookEventEntity, UUID>

// ── Processing service ──

/**
 * Handles inbound Augmont webhook notifications (KYC, Withdraw, Order,
 * Buy, Sell, Gateway Transaction, User Create, Redeem -- see Augmont's
 * webhook doc, "Message Schema and Details").
 *
 * KYC events update augmont_user_mappings.kycStatus (matched by uniqueId).
 * Buy/Sell events update the matching gold_transactions row (matched by
 * transactionId == our stored augmontTxnId) -- this catches async
 * cancellations that happen after our synchronous buy()/sell() response.
 *
 * All other event types (withdraw/order/gateway-transactions/user_create/
 * redeem) are logged to augmont_webhook_events only for now -- we don't
 * have a local withdraw-tracking or redeem-order feature to apply them
 * against yet. Every event, matched or not, is written to that audit
 * table so nothing is silently dropped.
 */
@Service
class AugmontWebhookService(
    private val eventRepo: AugmontWebhookEventRepository,
    private val goldTxnRepo: GoldTransactionRepository,
    private val augmontUserRepo: AugmontUserMappingRepository,
    private val objectMapper: ObjectMapper
) {
    private val log = LoggerFactory.getLogger(javaClass)

    // Maps Augmont's assorted status strings onto our own gold_transactions
    // status vocabulary (PENDING/SUCCESS/FAILED).
    private fun mapStatus(raw: String?): String = when (raw?.lowercase()?.trim()) {
        "completed", "complete", "not cancelled" -> "SUCCESS"
        "rejected", "cancelled" -> "FAILED"
        else -> "PENDING"
    }

    suspend fun handle(rawBody: String) {
        val root = objectMapper.readTree(rawBody)
        val type = root.get("type")?.asText() ?: "unknown"
        val dataArray = root.get("data")

        if (dataArray == null || !dataArray.isArray) {
            log.warn("Augmont webhook: no 'data' array for type={}, raw={}", type, rawBody)
            return
        }

        for (item in dataArray) {
            val status = item.get("status")?.asText()
            val uniqueId = item.get("uniqueId")?.asText()
            val transactionId = item.get("transactionId")?.asText()
            val merchantTransactionId = item.get("merchantTransactionId")?.asText()
            var matched = false

            try {
                when (type) {
                    "kyc" -> {
                        if (uniqueId != null) {
                            val mapping = augmontUserRepo.findByAugmontUniqueId(uniqueId)
                            if (mapping != null) {
                                augmontUserRepo.save(mapping.copy(
                                    kycStatus = status?.uppercase() ?: mapping.kycStatus,
                                    updatedAt = Instant.now()
                                ))
                                matched = true
                                log.info("Augmont webhook: KYC status -> {} for augmontUniqueId={}", status, uniqueId)
                            } else {
                                log.warn("Augmont webhook: KYC event for unknown uniqueId={}", uniqueId)
                            }
                        }
                    }
                    "buy", "sell" -> {
                        if (transactionId != null) {
                            val txn = goldTxnRepo.findByAugmontTxnId(transactionId)
                            if (txn != null) {
                                val cancelId = item.get("cancelId")?.takeIf { !it.isNull }?.asText()
                                val newStatus = if (!cancelId.isNullOrBlank()) "FAILED"
                                else mapStatus(status ?: item.get("transactionStatus")?.asText())
                                goldTxnRepo.save(txn.copy(status = newStatus))
                                matched = true
                                log.info("Augmont webhook: {} txn {} status -> {}", type, transactionId, newStatus)
                            } else {
                                log.warn("Augmont webhook: {} event for unmatched augmontTxnId={}", type, transactionId)
                            }
                        }
                    }
                    else -> {
                        // withdraw, order, gateway-transactions, user_create, redeem --
                        // no local feature/table to update against yet. Logged to
                        // the audit table below only; wire real handling once
                        // withdraw-tracking or redeem-order features exist.
                        log.info("Augmont webhook: type={} logged (no local handler wired yet)", type)
                    }
                }
            } catch (ex: Exception) {
                log.error("Augmont webhook: failed to process a {} item: {}", type, ex.message, ex)
            }

            eventRepo.save(AugmontWebhookEventEntity(
                eventType = type,
                status = status,
                uniqueId = uniqueId,
                transactionId = transactionId,
                merchantTransactionId = merchantTransactionId,
                matchedLocalRecord = matched,
                rawPayload = item.toString()
            ))
        }
    }
}

// ── Router ──

@Configuration
class AugmontWebhookRouter(
    private val webhookService: AugmontWebhookService,
    // Augmont's webhook auth is a static shared secret sent in the
    // Authorization header (not an HMAC signature -- confirmed from their
    // webhook doc's sample headers, e.g. "Authorization: $1234567#1").
    // Set via AUGMONT_WEBHOOK_SECRET once Augmont's team confirms the
    // value they'll be sending.
    @Value("\${youpi.augmont.webhook-secret:}") private val webhookSecret: String
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Bean
    fun augmontWebhookRoutes() = coRouter {
        "/v1/webhooks".nest {
            POST("/augmont") { handleWebhook(it) }
        }
    }

    private suspend fun handleWebhook(request: ServerRequest): ServerResponse {
        val authHeader = request.headers().firstHeader("Authorization")

        if (webhookSecret.isBlank() || authHeader != webhookSecret) {
            log.warn("Augmont webhook: rejected -- Authorization header mismatch")
            return ServerResponse.status(HttpStatus.UNAUTHORIZED)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(mapOf("response" to "Unauthorized"))
        }

        val rawBody = request.awaitBody<String>()

        return try {
            webhookService.handle(rawBody)
            // Augmont requires EXACTLY this response shape to consider the
            // message delivered -- anything else (including our normal
            // ApiResponse wrapper used elsewhere) is treated as a failed
            // delivery and queued for retry (3x every 5 min, then again
            // after 24h -- see their webhook doc, "Undeliverable Messages").
            ServerResponse.ok().contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(mapOf("response" to "Success"))
        } catch (ex: Exception) {
            log.error("Augmont webhook: processing failed: {}", ex.message, ex)
            ServerResponse.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValueAndAwait(mapOf("response" to "Failed"))
        }
    }
}