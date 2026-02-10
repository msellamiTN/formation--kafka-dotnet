package com.data2ai.kafka.producer.resilient.service;

import org.springframework.kafka.KafkaException;

/**
 * Minimal error classification for training purposes.
 *
 * In real systems you would map exceptions to retriable/permanent based on
 * Kafka error codes, network state, and idempotence/transactions configuration.
 */
public final class ErrorClassifier {

    private ErrorClassifier() {
    }

    public static boolean isTransient(Throwable ex) {
        // Spring wraps many producer errors in KafkaException.
        if (ex instanceof KafkaException) {
            return true;
        }

        // Timeouts / transient IO issues are typically retriable.
        String msg = ex.getMessage() == null ? "" : ex.getMessage().toLowerCase();
        return msg.contains("timeout") || msg.contains("tempor") || msg.contains("connection");
    }
}
