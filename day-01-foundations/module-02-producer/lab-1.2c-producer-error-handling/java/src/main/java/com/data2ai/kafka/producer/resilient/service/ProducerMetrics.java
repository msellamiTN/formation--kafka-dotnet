package com.data2ai.kafka.producer.resilient.service;

import java.util.Map;

public class ProducerMetrics {
    private long produced;
    private long failed;
    private long sentToDlq;
    private long retried;
    private boolean circuitOpen;
    private int consecutiveFailures;
    private Map<String, Long> errorCounts;

    public long getProduced() {
        return produced;
    }

    public void setProduced(long produced) {
        this.produced = produced;
    }

    public long getFailed() {
        return failed;
    }

    public void setFailed(long failed) {
        this.failed = failed;
    }

    public long getSentToDlq() {
        return sentToDlq;
    }

    public void setSentToDlq(long sentToDlq) {
        this.sentToDlq = sentToDlq;
    }

    public long getRetried() {
        return retried;
    }

    public void setRetried(long retried) {
        this.retried = retried;
    }

    public boolean isCircuitOpen() {
        return circuitOpen;
    }

    public void setCircuitOpen(boolean circuitOpen) {
        this.circuitOpen = circuitOpen;
    }

    public int getConsecutiveFailures() {
        return consecutiveFailures;
    }

    public void setConsecutiveFailures(int consecutiveFailures) {
        this.consecutiveFailures = consecutiveFailures;
    }

    public Map<String, Long> getErrorCounts() {
        return errorCounts;
    }

    public void setErrorCounts(Map<String, Long> errorCounts) {
        this.errorCounts = errorCounts;
    }
}
