package com.data2ai.kafka.consumer.balance.service;

import com.data2ai.kafka.consumer.balance.model.CustomerBalance;
import com.data2ai.kafka.consumer.balance.model.RebalancingEvent;
import com.data2ai.kafka.consumer.balance.model.Transaction;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.TopicPartition;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.listener.ConsumerSeekAware;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Balance consumer that tracks customer balances in-memory.
 * Uses Spring Kafka @KafkaListener with concurrency for consumer group scaling.
 * Implements ConsumerSeekAware to capture rebalancing events.
 */
@Service
public class BalanceService implements ConsumerSeekAware {

    private static final Logger log = LoggerFactory.getLogger(BalanceService.class);

    private final ObjectMapper objectMapper;

    // In-memory balance store (thread-safe)
    private final ConcurrentHashMap<String, CustomerBalance> balances = new ConcurrentHashMap<>();

    // Rebalancing history
    private final CopyOnWriteArrayList<RebalancingEvent> rebalancingHistory = new CopyOnWriteArrayList<>();

    // Assigned partitions per thread
    private final CopyOnWriteArrayList<Integer> assignedPartitions = new CopyOnWriteArrayList<>();

    // Metrics
    private final AtomicLong messagesConsumed = new AtomicLong();
    private final AtomicLong balanceUpdates = new AtomicLong();
    private final AtomicLong processingErrors = new AtomicLong();
    private final Instant startedAt = Instant.now();
    private volatile Instant lastMessageAt;

    public BalanceService(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @KafkaListener(topics = "${app.kafka.topic}")
    public void onMessage(ConsumerRecord<String, String> record) {
        messagesConsumed.incrementAndGet();
        lastMessageAt = Instant.now();

        try {
            Transaction tx = objectMapper.readValue(record.value(), Transaction.class);
            String customerId = tx.getCustomerId();
            if (customerId == null || customerId.isBlank()) {
                log.warn("Skipping transaction with no customerId. partition={} offset={}",
                        record.partition(), record.offset());
                return;
            }

            // Compute balance delta based on transaction type
            BigDecimal delta = computeDelta(tx);

            balances.compute(customerId, (key, existing) -> {
                CustomerBalance bal = (existing != null) ? existing : new CustomerBalance(key);
                bal.setBalance(bal.getBalance().add(delta));
                bal.setTransactionCount(bal.getTransactionCount() + 1);
                bal.setLastUpdated(Instant.now());
                return bal;
            });

            balanceUpdates.incrementAndGet();

            log.debug("Balance updated: customerId={} delta={} partition={} offset={}",
                    customerId, delta, record.partition(), record.offset());

        } catch (Exception ex) {
            processingErrors.incrementAndGet();
            log.error("Processing error. partition={} offset={} error={}",
                    record.partition(), record.offset(), ex.getMessage());
        }
    }

    // --- ConsumerSeekAware callbacks for rebalancing tracking ---

    @Override
    public void onPartitionsAssigned(Map<TopicPartition, Long> assignments, ConsumerSeekCallback callback) {
        List<Integer> partitionIds = assignments.keySet().stream()
                .map(TopicPartition::partition).sorted().toList();

        assignedPartitions.clear();
        assignedPartitions.addAll(partitionIds);

        RebalancingEvent event = new RebalancingEvent();
        event.setEventType("Assigned");
        event.setPartitions(partitionIds);
        event.setDetails("Received " + partitionIds.size() + " partitions");
        rebalancingHistory.add(event);

        log.info("Partitions ASSIGNED: {}", partitionIds);
    }

    @Override
    public void onPartitionsRevoked(Collection<TopicPartition> partitions) {
        List<Integer> partitionIds = partitions.stream()
                .map(TopicPartition::partition).sorted().toList();

        RebalancingEvent event = new RebalancingEvent();
        event.setEventType("Revoked");
        event.setPartitions(partitionIds);
        event.setDetails("Lost " + partitionIds.size() + " partitions (rebalancing)");
        rebalancingHistory.add(event);

        log.warn("Partitions REVOKED: {}", partitionIds);
    }

    // --- Public accessors for controller ---

    public Map<String, CustomerBalance> getBalances() {
        return Collections.unmodifiableMap(balances);
    }

    public CustomerBalance getBalance(String customerId) {
        return balances.get(customerId);
    }

    public List<RebalancingEvent> getRebalancingHistory() {
        return Collections.unmodifiableList(rebalancingHistory);
    }

    public List<Integer> getAssignedPartitions() {
        return Collections.unmodifiableList(assignedPartitions);
    }

    public Map<String, Object> getMetrics() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("messagesConsumed", messagesConsumed.get());
        m.put("balanceUpdates", balanceUpdates.get());
        m.put("processingErrors", processingErrors.get());
        m.put("uniqueCustomers", balances.size());
        m.put("assignedPartitions", assignedPartitions);
        m.put("rebalancingEvents", rebalancingHistory.size());
        m.put("startedAt", startedAt.toString());
        m.put("lastMessageAt", lastMessageAt != null ? lastMessageAt.toString() : null);
        return m;
    }

    // --- Private helpers ---

    private BigDecimal computeDelta(Transaction tx) {
        if (tx.getAmount() == null) return BigDecimal.ZERO;
        String type = tx.getType() != null ? tx.getType().toUpperCase() : "";
        return switch (type) {
            case "DEPOSIT" -> tx.getAmount();
            case "WITHDRAWAL", "PAYMENT" -> tx.getAmount().negate();
            default -> tx.getAmount(); // TRANSFER treated as credit for simplicity
        };
    }
}
