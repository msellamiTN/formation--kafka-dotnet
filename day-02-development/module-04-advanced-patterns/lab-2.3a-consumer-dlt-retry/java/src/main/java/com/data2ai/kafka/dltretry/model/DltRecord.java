package com.data2ai.kafka.dltretry.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class DltRecord {
    private String originalTransactionId;
    private String errorMessage;
    private String errorType;
    private int retryCount;
    private Instant failedAt;
    private Transaction originalTransaction;
}
