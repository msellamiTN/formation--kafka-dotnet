package com.data2ai.kafka.service;

import com.data2ai.kafka.model.Order;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class OrderService {

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final DltService dltService;
    private final ObjectMapper objectMapper;

    @Value("${KAFKA_TOPIC:orders}")
    private String topic;

    private final AtomicBoolean simulateTransientError = new AtomicBoolean(false);
    private final AtomicLong successCount = new AtomicLong(0);
    private final AtomicLong errorCount = new AtomicLong(0);
    private final AtomicLong dltCount = new AtomicLong(0);

    public OrderService(KafkaTemplate<String, String> kafkaTemplate, 
                       DltService dltService,
                       ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.dltService = dltService;
        this.objectMapper = objectMapper;
    }

    public CompletableFuture<SendResult<String, String>> sendOrder(Order order) {
        try {
            order.validate();
            
            if (simulateTransientError.get()) {
                throw new TransientException("Simulated transient error");
            }
            
            String value = objectMapper.writeValueAsString(order);
            System.out.println("Sending order: " + order.getOrderId());
            
            return kafkaTemplate.send(topic, order.getOrderId(), value)
                .whenComplete((result, ex) -> {
                    if (ex == null) {
                        successCount.incrementAndGet();
                        System.out.println("Order sent successfully: " + order.getOrderId() + 
                            " to partition " + result.getRecordMetadata().partition() + 
                            " offset " + result.getRecordMetadata().offset());
                    } else {
                        errorCount.incrementAndGet();
                        System.err.println("Failed to send order: " + order.getOrderId() + 
                            " - " + ex.getMessage());
                    }
                });
                
        } catch (IllegalArgumentException e) {
            errorCount.incrementAndGet();
            dltCount.incrementAndGet();
            dltService.sendToDlt(order, e, topic, 0);
            throw new PermanentException("Validation failed: " + e.getMessage(), e);
            
        } catch (TransientException e) {
            errorCount.incrementAndGet();
            throw e;
            
        } catch (Exception e) {
            errorCount.incrementAndGet();
            throw new RuntimeException("Error processing order: " + e.getMessage(), e);
        }
    }

    public void setSimulateTransientError(boolean enabled) {
        simulateTransientError.set(enabled);
        System.out.println("Transient error simulation: " + (enabled ? "ENABLED" : "DISABLED"));
    }

    public boolean isSimulatingTransientError() {
        return simulateTransientError.get();
    }

    public Stats getStats() {
        return new Stats(successCount.get(), errorCount.get(), dltCount.get());
    }

    public static class Stats {
        public final long success;
        public final long errors;
        public final long dlt;

        public Stats(long success, long errors, long dlt) {
            this.success = success;
            this.errors = errors;
            this.dlt = dlt;
        }
    }

    public static class TransientException extends RuntimeException {
        public TransientException(String message) {
            super(message);
        }
    }

    public static class PermanentException extends RuntimeException {
        public PermanentException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
