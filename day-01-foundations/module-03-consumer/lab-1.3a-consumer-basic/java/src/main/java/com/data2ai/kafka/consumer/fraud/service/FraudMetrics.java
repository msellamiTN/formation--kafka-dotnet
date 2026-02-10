package com.data2ai.kafka.consumer.fraud.service;

import java.time.Instant;

public class FraudMetrics {
    private long messagesConsumed;
    private long fraudAlerts;
    private long processingErrors;
    private double averageRiskScore;
    private Instant startedAt;
    private Instant lastMessageAt;

    public long getMessagesConsumed() {
        return messagesConsumed;
    }

    public void setMessagesConsumed(long messagesConsumed) {
        this.messagesConsumed = messagesConsumed;
    }

    public long getFraudAlerts() {
        return fraudAlerts;
    }

    public void setFraudAlerts(long fraudAlerts) {
        this.fraudAlerts = fraudAlerts;
    }

    public long getProcessingErrors() {
        return processingErrors;
    }

    public void setProcessingErrors(long processingErrors) {
        this.processingErrors = processingErrors;
    }

    public double getAverageRiskScore() {
        return averageRiskScore;
    }

    public void setAverageRiskScore(double averageRiskScore) {
        this.averageRiskScore = averageRiskScore;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public void setStartedAt(Instant startedAt) {
        this.startedAt = startedAt;
    }

    public Instant getLastMessageAt() {
        return lastMessageAt;
    }

    public void setLastMessageAt(Instant lastMessageAt) {
        this.lastMessageAt = lastMessageAt;
    }
}
