package com.data2ai.kafka.consumer.audit.model;

import java.time.Instant;

public class AuditRecord {
    private String transactionId;
    private String customerId;
    private String rawPayload;
    private int partition;
    private long offset;
    private Instant auditedAt;

    public String getTransactionId() { return transactionId; }
    public void setTransactionId(String transactionId) { this.transactionId = transactionId; }

    public String getCustomerId() { return customerId; }
    public void setCustomerId(String customerId) { this.customerId = customerId; }

    public String getRawPayload() { return rawPayload; }
    public void setRawPayload(String rawPayload) { this.rawPayload = rawPayload; }

    public int getPartition() { return partition; }
    public void setPartition(int partition) { this.partition = partition; }

    public long getOffset() { return offset; }
    public void setOffset(long offset) { this.offset = offset; }

    public Instant getAuditedAt() { return auditedAt; }
    public void setAuditedAt(Instant auditedAt) { this.auditedAt = auditedAt; }
}
