package com.data2ai.kafka.consumer.balance.model;

import java.math.BigDecimal;
import java.time.Instant;

public class CustomerBalance {
    private String customerId;
    private BigDecimal balance;
    private long transactionCount;
    private Instant lastUpdated;

    public CustomerBalance() {
        this.balance = BigDecimal.ZERO;
        this.transactionCount = 0;
    }

    public CustomerBalance(String customerId) {
        this();
        this.customerId = customerId;
    }

    public String getCustomerId() { return customerId; }
    public void setCustomerId(String customerId) { this.customerId = customerId; }

    public BigDecimal getBalance() { return balance; }
    public void setBalance(BigDecimal balance) { this.balance = balance; }

    public long getTransactionCount() { return transactionCount; }
    public void setTransactionCount(long transactionCount) { this.transactionCount = transactionCount; }

    public Instant getLastUpdated() { return lastUpdated; }
    public void setLastUpdated(Instant lastUpdated) { this.lastUpdated = lastUpdated; }
}
