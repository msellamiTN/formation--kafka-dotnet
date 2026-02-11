package com.data2ai.kafka.serialization.consumer;

import com.data2ai.kafka.serialization.model.Transaction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Headers;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

@Service
public class SerializationConsumerService {
    
    private static final Logger log = LoggerFactory.getLogger(SerializationConsumerService.class);
    
    private final AtomicInteger processedCount = new AtomicInteger(0);
    private final AtomicInteger errorCount = new AtomicInteger(0);
    private final Map<String, AtomicInteger> schemaVersionCounts = new HashMap<>();
    
    @KafkaListener(
        topics = "${app.kafka.topic:banking.transactions}",
        groupId = "serialization-consumer-group"
    )
    public void consumeTransaction(
            Transaction transaction,
            @Headers Map<String, Object> headers) {
        
        try {
            log.info("Processing transaction: {} | Amount: {} {} | Customer: {}",
                    transaction.getTransactionId(),
                    transaction.getAmount(),
                    transaction.getCurrency(),
                    transaction.getCustomerId());
            
            // Process transaction
            processTransaction(transaction);
            
            // Track schema version
            String schemaVersion = (String) headers.getOrDefault("schema-version", "unknown");
            schemaVersionCounts.computeIfAbsent(schemaVersion, k -> new AtomicInteger(0))
                              .incrementAndGet();
            
            processedCount.incrementAndGet();
            
            log.info("Transaction processed successfully: {} | Total processed: {}",
                    transaction.getTransactionId(), processedCount.get());
            
        } catch (Exception e) {
            errorCount.incrementAndGet();
            log.error("Failed to process transaction: {} | Error: {}",
                    transaction.getTransactionId(), e.getMessage(), e);
            throw e; // Re-throw to trigger Kafka retry mechanism
        }
    }
    
    private void processTransaction(Transaction transaction) {
        // Simulate business logic
        log.debug("Processing transaction: {}", transaction.getTransactionId());
        
        // Business validation
        if (transaction.getAmount().compareTo(new BigDecimal("10000")) > 0) {
            log.warn("Large transaction detected: {} | Amount: {}",
                    transaction.getTransactionId(), transaction.getAmount());
        }
        
        // Simulate processing time
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        
        log.debug("Transaction validation completed: {}", transaction.getTransactionId());
    }
    
    public Map<String, Object> getStatistics() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("processed", processedCount.get());
        stats.put("errors", errorCount.get());
        stats.put("successRate", calculateSuccessRate());
        stats.put("schemaVersions", schemaVersionCounts.entrySet().stream()
                .collect(Collectors.toMap(
                    Map.Entry::getKey,
                    e -> e.getValue().get()
                )));
        stats.put("timestamp", Instant.now().toString());
        return stats;
    }
    
    private double calculateSuccessRate() {
        int total = processedCount.get() + errorCount.get();
        return total > 0 ? (double) processedCount.get() / total * 100 : 0.0;
    }
}
