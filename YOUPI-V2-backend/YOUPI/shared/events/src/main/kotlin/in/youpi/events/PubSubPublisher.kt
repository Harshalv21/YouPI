package `in`.youpi.events

import com.google.api.core.ApiFutures
import com.google.cloud.pubsub.v1.Publisher
import com.google.protobuf.ByteString
import com.google.pubsub.v1.PubsubMessage
import com.google.pubsub.v1.TopicName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import com.fasterxml.jackson.databind.ObjectMapper
import jakarta.annotation.PreDestroy
import java.util.concurrent.ConcurrentHashMap

/**
 * Google Cloud Pub/Sub publisher.
 * Lazy-initializes publishers per topic and reuses them.
 * Publishes events as JSON with metadata attributes.
 */
@Service
class PubSubPublisher(
    @Value("\${youpi.firebase.project-id:you-pi-55f85}") private val projectId: String,
    private val objectMapper: ObjectMapper
) {

    private val log = LoggerFactory.getLogger(javaClass)
    private val publishers = ConcurrentHashMap<String, Publisher>()

    companion object {
        // Topic names
        const val RECHARGE_INITIATED = "recharge-initiated"
        const val PAYMENT_CAPTURED = "payment-captured"
        const val GOLD_PURCHASE = "gold-purchase"
        const val BNPL_APPLICATION = "bnpl-application-submitted"
        const val LOAN_APPLICATION = "loan-application-submitted"
        const val DEAD_LETTER = "youpi-dead-letter"
    }

    /**
     * Publish a message to a Pub/Sub topic.
     *
     * @param topic topic name
     * @param data the payload object (serialized to JSON)
     * @param attributes optional message attributes
     * @return message ID
     */
    suspend fun publish(
        topic: String,
        data: Any,
        attributes: Map<String, String> = emptyMap()
    ): String {
        val publisher = getOrCreatePublisher(topic)

        val json = objectMapper.writeValueAsString(data)
        val message = PubsubMessage.newBuilder()
            .setData(ByteString.copyFromUtf8(json))
            .putAllAttributes(attributes)
            .build()

        return withContext(Dispatchers.IO) {
            try {
                val messageId = ApiFutures.addCallback(
                    publisher.publish(message),
                    object : com.google.api.core.ApiFutureCallback<String> {
                        override fun onSuccess(result: String) {
                            log.debug("Published to {}: messageId={}", topic, result)
                        }
                        override fun onFailure(t: Throwable) {
                            log.error("Failed to publish to {}: {}", topic, t.message, t)
                        }
                    },
                    com.google.common.util.concurrent.MoreExecutors.directExecutor()
                )
                publisher.publish(message).get()
            } catch (e: Exception) {
                log.error("Pub/Sub publish failed for topic={}: {}", topic, e.message, e)
                throw e
            }
        }
    }

    private fun getOrCreatePublisher(topic: String): Publisher {
        return publishers.computeIfAbsent(topic) {
            Publisher.newBuilder(TopicName.of(projectId, topic)).build()
        }
    }

    @PreDestroy
    fun shutdown() {
        publishers.values.forEach { publisher ->
            try {
                publisher.shutdown()
            } catch (e: Exception) {
                log.warn("Error shutting down publisher: {}", e.message)
            }
        }
    }
}
