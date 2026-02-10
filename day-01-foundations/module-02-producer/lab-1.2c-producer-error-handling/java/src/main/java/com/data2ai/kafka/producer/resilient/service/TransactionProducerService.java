package com.data2ai.kafka.producer.resilient.service;

import com.data2ai.kafka.producer.resilient.model.Transaction;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class TransactionProducerService {

    private static final Logger log = LoggerFactory.getLogger(TransactionProducerService.class);

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    @Value("${app.kafka.topic}")
    private String topic;

    @Value("${app.kafka.dlq-topic}")
    private String dlqTopic;

    @Value("${app.retry.max-attempts}")
    private int maxAttempts;

    @Value("${app.retry.base-backoff-ms}")
    private long baseBackoffMs;

    @Value("${app.circuit.max-consecutive-failures}")
    private int circuitThreshold;

    @Value("${app.circuit.open-duration-ms}")
    private long circuitOpenDurationMs;

    // Metrics
    private final AtomicLong produced = new AtomicLong();
    private final AtomicLong failed = new AtomicLong();
    private final AtomicLong sentToDlq = new AtomicLong();
    private final AtomicLong retried = new AtomicLong();

    private final AtomicInteger consecutiveFailures = new AtomicInteger();
    private volatile long circuitOpenedAtMs = -1L;

    private final ConcurrentHashMap<String, AtomicLong> errorCounts = new ConcurrentHashMap<>();

    public TransactionProducerService(KafkaTemplate<String, String> kafkaTemplate, ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    /**
     * Produce with explicit retry + exponential backoff + DLQ.
     *
     * Important: this is a training implementation.
     * In production you may prefer letting the Kafka client handle retriable errors,
     * but still keep a DLQ for permanent failures or business validation failures.
     */
    public CompletableFuture<Map<String, Object>> sendWithRetryAsync(Transaction tx) throws Exception {
        if (isCircuitOpen()) {
            return sendToDlqAsync(tx, "CircuitBreakerOpen")
                    .thenApply(_ignored -> Map.of(
                            "status", "SENT_TO_DLQ",
                            "reason", "Circuit breaker open",
                            "dlqTopic", dlqTopic
                    ));
        }

        String key = tx.getCustomerId();
        String payload = objectMapper.writeValueAsString(tx);

        CompletableFuture<Map<String, Object>> promise = new CompletableFuture<>();
        attemptSend(tx, key, payload, 1, promise);
        return promise;
    }

    private void attemptSend(Transaction tx, String key, String payload, int attempt,
                             CompletableFuture<Map<String, Object>> promise) {
        kafkaTemplate.send(topic, key, payload)
                .whenComplete((result, ex) -> {
                    if (ex == null) {
                        onSuccess(result, promise, attempt);
                        return;
                    }

                    onFailure(ex);

                    boolean transientError = ErrorClassifier.isTransient(ex);
                    boolean canRetry = transientError && attempt < maxAttempts;

                    if (canRetry) {
                        retried.incrementAndGet();
                        long delayMs = computeBackoffMs(attempt);
                        log.warn("Transient error producing txId={} attempt={}/{}. Retrying in {}ms. Error={}",
                                tx.getTransactionId(), attempt, maxAttempts, delayMs, ex.getMessage());

                        // Avoid blocking Kafka sender threads. Use a simple async delay.
                        CompletableFuture.delayedExecutor(delayMs, java.util.concurrent.TimeUnit.MILLISECONDS)
                                .execute(() -> attemptSend(tx, key, payload, attempt + 1, promise));
                        return;
                    }

                    // Permanent or retries exhausted => DLQ
                    String reason = transientError ? "RetriesExhausted" : "PermanentError";
                    sendToDlqAsync(tx, reason)
                            .whenComplete((_ignored, dlqEx) -> {
                                if (dlqEx != null) {
                                    failed.incrementAndGet();
                                    promise.complete(Map.of(
                                            "status", "FAILED",
                                            "reason", reason,
                                            "error", ex.getMessage(),
                                            "dlqError", dlqEx.getMessage()
                                    ));
                                } else {
                                    promise.complete(Map.of(
                                            "status", "SENT_TO_DLQ",
                                            "reason", reason,
                                            "error", ex.getMessage(),
                                            "dlqTopic", dlqTopic
                                    ));
                                }
                            });
                });
    }

    private void onSuccess(SendResult<String, String> result,
                           CompletableFuture<Map<String, Object>> promise,
                           int attempts) {
        produced.incrementAndGet();
        consecutiveFailures.set(0);
        circuitOpenedAtMs = -1L;

        RecordMetadata md = result.getRecordMetadata();
        promise.complete(Map.of(
                "status", "PRODUCED",
                "topic", md.topic(),
                "partition", md.partition(),
                "offset", md.offset(),
                "timestamp", Instant.ofEpochMilli(md.timestamp()).toString(),
                "attempts", attempts
        ));
    }

    private void onFailure(Throwable ex) {
        int failures = consecutiveFailures.incrementAndGet();
        if (failures >= circuitThreshold && circuitOpenedAtMs < 0) {
            circuitOpenedAtMs = System.currentTimeMillis();
        }

        String key = ex.getClass().getSimpleName();
        errorCounts.computeIfAbsent(key, _k -> new AtomicLong()).incrementAndGet();
    }

    private long computeBackoffMs(int attempt) {
        // attempt=1 => base, attempt=2 => 2*base, attempt=3 => 4*base
        long factor = 1L << Math.max(0, attempt - 1);
        return Math.min(baseBackoffMs * factor, 30_000L);
    }

    private boolean isCircuitOpen() {
        if (circuitOpenedAtMs < 0) {
            return false;
        }

        long now = System.currentTimeMillis();
        if (now - circuitOpenedAtMs > circuitOpenDurationMs) {
            // half-open: allow traffic again
            circuitOpenedAtMs = -1L;
            consecutiveFailures.set(0);
            return false;
        }

        return true;
    }

    private CompletableFuture<Void> sendToDlqAsync(Transaction tx, String reason) {
        try {
            String key = tx.getCustomerId();
            String payload = objectMapper.writeValueAsString(tx);

            // Add minimal headers for diagnostics / forensics.
            ProducerRecord<String, String> record = new ProducerRecord<>(dlqTopic, key, payload);
            record.headers().add("original-topic", topic.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            record.headers().add("error-reason", reason.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            record.headers().add("transaction-id", tx.getTransactionId().getBytes(java.nio.charset.StandardCharsets.UTF_8));
            record.headers().add("failed-at", Instant.now().toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));

            return kafkaTemplate.send(record)
                    .thenApply(_sr -> {
                        sentToDlq.incrementAndGet();
                        log.warn("Sent txId={} to DLQ topic={} reason={}", tx.getTransactionId(), dlqTopic, reason);
                        return null;
                    });
        } catch (Exception ex) {
            CompletableFuture<Void> failedFuture = new CompletableFuture<>();
            failedFuture.completeExceptionally(ex);
            return failedFuture;
        }
    }

    public ProducerMetrics getMetrics() {
        ProducerMetrics m = new ProducerMetrics();
        m.setProduced(produced.get());
        m.setFailed(failed.get());
        m.setSentToDlq(sentToDlq.get());
        m.setRetried(retried.get());
        m.setCircuitOpen(isCircuitOpen());
        m.setConsecutiveFailures(consecutiveFailures.get());

        Map<String, Long> counts = new HashMap<>();
        for (var e : errorCounts.entrySet()) {
            counts.put(e.getKey(), e.getValue().get());
        }
        m.setErrorCounts(counts);
        return m;
    }
}
