package com.data2ai.kafka.consumer.balance.model;

import java.time.Instant;
import java.util.List;

public class RebalancingEvent {
    private String eventType;
    private List<Integer> partitions;
    private String details;
    private Instant timestamp;

    public RebalancingEvent() {
        this.timestamp = Instant.now();
    }

    public String getEventType() { return eventType; }
    public void setEventType(String eventType) { this.eventType = eventType; }

    public List<Integer> getPartitions() { return partitions; }
    public void setPartitions(List<Integer> partitions) { this.partitions = partitions; }

    public String getDetails() { return details; }
    public void setDetails(String details) { this.details = details; }

    public Instant getTimestamp() { return timestamp; }
    public void setTimestamp(Instant timestamp) { this.timestamp = timestamp; }
}
