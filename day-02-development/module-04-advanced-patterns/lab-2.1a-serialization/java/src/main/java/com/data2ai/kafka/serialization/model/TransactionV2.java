package com.data2ai.kafka.serialization.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.Instant;

@Data
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class TransactionV2 {
    private String transactionId;
    private String customerId;
    private String fromAccount;
    private String toAccount;
    private BigDecimal amount;
    private String currency;
    private Transaction.TransactionType type;
    private Transaction.TransactionStatus status;
    private Instant timestamp;
    private String description;
    
    // New fields in V2
    private String category;
    private String priority;
    private Integer riskScore;
}
