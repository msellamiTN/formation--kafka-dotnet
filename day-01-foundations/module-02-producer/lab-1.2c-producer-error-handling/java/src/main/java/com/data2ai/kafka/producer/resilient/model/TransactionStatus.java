package com.data2ai.kafka.producer.resilient.model;

public enum TransactionStatus {
    PENDING,
    PROCESSING,
    COMPLETED,
    FAILED,
    REJECTED
}
