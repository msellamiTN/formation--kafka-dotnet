package com.data2ai.kafka.serialization.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class Transaction {
    private String transactionId;
    private String customerId;
    private String fromAccount;
    private String toAccount;
    private BigDecimal amount;
    private String currency;
    private TransactionType type;
    private TransactionStatus status;
    private Instant timestamp;
    private String description;
    
    // Schema evolution - new field in V2
    private String category;
    private Map<String, Object> metadata;
    
    public enum TransactionType {
        WITHDRAWAL, PAYMENT, CARD_PAYMENT, TRANSFER, 
        INTERNATIONAL_TRANSFER, BILL_PAYMENT, DEPOSIT
    }
    
    public enum TransactionStatus {
        PENDING, COMPLETED, FAILED, CANCELLED
    }
}
