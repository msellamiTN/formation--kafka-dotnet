package com.data2ai.kafka.producer.keyed.service;

import com.data2ai.kafka.producer.keyed.model.Transaction;
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
     * Produces a transaction using customerId as key.
     *
     * Keying by customerId ensures all events for one customer go to the same partition,
     * therefore preserving ordering per customer.
     */
    public CompletableFuture<Map<String, Object>> sendAsync(Transaction tx) throws Exception {
        String key = tx.getCustomerId();
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
