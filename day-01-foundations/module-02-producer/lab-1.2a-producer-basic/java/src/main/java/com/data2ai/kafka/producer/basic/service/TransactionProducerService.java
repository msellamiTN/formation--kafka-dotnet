package com.data2ai.kafka.producer.basic.service;

import com.data2ai.kafka.producer.basic.model.Transaction;
import com.fasterxml.jackson.databind.ObjectMapper;
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
public class TransactionProducerService {

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    @Value("${app.kafka.topic}")
    private String topic;

    public TransactionProducerService(KafkaTemplate<String, String> kafkaTemplate, ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    /**
     * Produces a transaction to Kafka.
     *
     * Implementation notes:
     * - The key uses transactionId for Lab 1.2A (Lab 1.2B uses customerId to guarantee ordering per customer).
     * - We return delivery metadata to help students understand partitions/offsets.
     */
    public CompletableFuture<Map<String, Object>> sendAsync(Transaction tx) throws Exception {
        String key = tx.getTransactionId();
        String payload = objectMapper.writeValueAsString(tx);

        return kafkaTemplate.send(topic, key, payload)
                .thenApply(this::toResponse);
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
