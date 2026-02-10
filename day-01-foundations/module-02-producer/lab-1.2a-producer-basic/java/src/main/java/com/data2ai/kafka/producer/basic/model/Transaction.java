package com.data2ai.kafka.producer.basic.model;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * Banking transaction payload sent to Kafka.
 *
 * Security note:
 * - Keep this DTO minimal and validated.
 * - Never log sensitive fields (e.g., full account numbers) in real systems.
 */
public class Transaction {

    @NotBlank
    private String transactionId = UUID.randomUUID().toString();

    @NotBlank
    @Size(min = 10, max = 34)
    private String fromAccount;

    @NotBlank
    @Size(min = 10, max = 34)
    private String toAccount;

    @NotNull
    @DecimalMin(value = "0.01")
    private BigDecimal amount;

    @NotBlank
    @Size(min = 3, max = 3)
    private String currency = "EUR";

    @NotNull
    private TransactionType type;

    @Size(max = 500)
    private String description;

    @NotBlank
    private String customerId;

    @NotNull
    private Instant timestamp = Instant.now();

    @Min(0)
    @Max(100)
    private int riskScore = 0;

    @NotNull
    private TransactionStatus status = TransactionStatus.PENDING;

    public String getTransactionId() {
        return transactionId;
    }

    public void setTransactionId(String transactionId) {
        this.transactionId = transactionId;
    }

    public String getFromAccount() {
        return fromAccount;
    }

    public void setFromAccount(String fromAccount) {
        this.fromAccount = fromAccount;
    }

    public String getToAccount() {
        return toAccount;
    }

    public void setToAccount(String toAccount) {
        this.toAccount = toAccount;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public String getCurrency() {
        return currency;
    }

    public void setCurrency(String currency) {
        this.currency = currency;
    }

    public TransactionType getType() {
        return type;
    }

    public void setType(TransactionType type) {
        this.type = type;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getCustomerId() {
        return customerId;
    }

    public void setCustomerId(String customerId) {
        this.customerId = customerId;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }

    public int getRiskScore() {
        return riskScore;
    }

    public void setRiskScore(int riskScore) {
        this.riskScore = riskScore;
    }

    public TransactionStatus getStatus() {
        return status;
    }

    public void setStatus(TransactionStatus status) {
        this.status = status;
    }
}
