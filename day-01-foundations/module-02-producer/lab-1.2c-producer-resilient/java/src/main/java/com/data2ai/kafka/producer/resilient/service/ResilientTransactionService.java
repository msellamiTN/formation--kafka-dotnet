package com.data2ai.kafka.producer.resilient.service;

import com.data2ai.kafka.producer.resilient.model.Transaction;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.retry.annotation.Retry;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

@Service
public class ResilientTransactionService {

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    @Value("${app.kafka.topic}")
    private String topic;

    public ResilientTransactionService(KafkaTemplate<String, String> kafkaTemplate, ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    /**
     * Produces a transaction to Kafka with retry and circuit breaker.
     *
     * Implementation notes:
     * - Uses transactionId as key for partitioning
     * - Includes retry mechanism for transient failures
     * - Circuit breaker opens after repeated failures
     * - Returns delivery metadata for partition/offset tracking
     */
    @Retry(name = "kafkaProducer", fallbackMethod = "sendToDlq")
    @CircuitBreaker(name = "kafkaProducer", fallbackMethod = "sendToDlq")
    public CompletableFuture<Map<String, Object>> sendWithRetry(Transaction tx) throws Exception {
        String key = tx.getTransactionId();
        String payload = objectMapper.writeValueAsString(tx);

        return kafkaTemplate.send(topic, key, payload)
                .thenApply(this::toResponse);
    }

    /**
     * Fallback method that sends failed transactions to DLQ
     */
    public CompletableFuture<Map<String, Object>> sendToDlq(Transaction tx, Exception ex) {
        String dlqTopic = topic + ".dlq";
        String key = tx.getTransactionId();
        
        try {
            String payload = objectMapper.writeValueAsString(tx);
            return kafkaTemplate.send(dlqTopic, key, payload)
                    .thenApply(result -> {
                        Map<String, Object> response = new HashMap<>();
                        response.put("status", "SENT_TO_DLQ");
                        response.put("reason", ex.getMessage());
                        response.put("dlqTopic", dlqTopic);
                        return response;
                    });
        } catch (Exception dlqEx) {
            CompletableFuture<Map<String, Object>> failed = new CompletableFuture<>();
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("status", "FAILED");
            errorResponse.put("error", "Failed to send to DLQ: " + dlqEx.getMessage());
            failed.complete(errorResponse);
            return failed;
        }
    }

    private Map<String, Object> toResponse(SendResult<String, String> result) {
        RecordMetadata md = result.getRecordMetadata();

        Map<String, Object> response = new HashMap<>();
        response.put("status", "PRODUCED");
        response.put("topic", md.topic());
        response.put("partition", md.partition());
        response.put("offset", md.offset());
        response.put("timestamp", Instant.ofEpochMilli(md.timestamp()).toString());
        return response;
    }
}
