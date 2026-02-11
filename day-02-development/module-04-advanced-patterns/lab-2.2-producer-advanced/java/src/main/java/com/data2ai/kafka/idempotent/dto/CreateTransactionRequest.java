package com.data2ai.kafka.idempotent.dto;

import com.data2ai.kafka.idempotent.model.Transaction;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class CreateTransactionRequest {
    private String fromAccount;
    private String toAccount;
    private BigDecimal amount;
    private String currency;
    private Transaction.TransactionType type;
    private String description;
    private String customerId;
}
