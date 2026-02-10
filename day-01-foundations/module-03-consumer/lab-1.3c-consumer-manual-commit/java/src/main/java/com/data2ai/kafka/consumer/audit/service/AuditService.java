package com.data2ai.kafka.consumer.audit.service;

import com.data2ai.kafka.consumer.audit.model.AuditRecord;
import com.data2ai.kafka.consumer.audit.model.Transaction;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.header.internals.RecordHeader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Audit consumer with manual commit (at-least-once), retry, and DLQ.
 * Uses Spring Kafka MANUAL ack mode — offsets are committed only after
 * successful processing (or DLQ forwarding).
 */
@Service
public class AuditService {

    private static final Logger log = LoggerFactory.getLogger(AuditService.class);

    private final ObjectMapper objectMapper;
    private final KafkaTemplate<String, String> kafkaTemplate;

    @Value("${app.kafka.dlq-topic}")
    private String dlqTopic;

    @Value("${app.retry.max-attempts}")
    private int maxRetryAttempts;

    @Value("${app.retry.backoff-ms}")
    private long retryBackoffMs;

    // Idempotent audit log (keyed by transactionId)
    private final ConcurrentHashMap<String, AuditRecord> auditLog = new ConcurrentHashMap<>();

    // DLQ messages
    private final CopyOnWriteArrayList<Map<String, Object>> dlqMessages = new CopyOnWriteArrayList<>();

    // Metrics
    private final AtomicLong messagesConsumed = new AtomicLong();
    private final AtomicLong auditRecords = new AtomicLong();
    private final AtomicLong duplicatesSkipped = new AtomicLong();
    private final AtomicLong processingErrors = new AtomicLong();
    private final AtomicLong dlqCount = new AtomicLong();
    private final AtomicLong manualCommits = new AtomicLong();
    private final Instant startedAt = Instant.now();
    private volatile Instant lastMessageAt;
    private volatile Instant lastCommitAt;

    public AuditService(ObjectMapper objectMapper, KafkaTemplate<String, String> kafkaTemplate) {
        this.objectMapper = objectMapper;
        this.kafkaTemplate = kafkaTemplate;
    }

    @KafkaListener(topics = "${app.kafka.topic}")
    public void onMessage(ConsumerRecord<String, String> record, Acknowledgment ack) {
        messagesConsumed.incrementAndGet();
        lastMessageAt = Instant.now();

        boolean processed = false;

        for (int attempt = 1; attempt <= maxRetryAttempts; attempt++) {
            try {
                processRecord(record);
                processed = true;
                break;
            } catch (Exception ex) {
                processingErrors.incrementAndGet();
                log.warn("Processing attempt {}/{} failed. partition={} offset={} error={}",
                        attempt, maxRetryAttempts, record.partition(), record.offset(), ex.getMessage());

                if (attempt < maxRetryAttempts) {
                    try {
                        Thread.sleep(retryBackoffMs * attempt);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
        }

        // If all retries failed, send to DLQ
        if (!processed) {
            sendToDlq(record);
        }

        // Acknowledge (commit) regardless — message is either processed or in DLQ
        ack.acknowledge();
        manualCommits.incrementAndGet();
        lastCommitAt = Instant.now();
    }

    private void processRecord(ConsumerRecord<String, String> record) throws Exception {
        Transaction tx = objectMapper.readValue(record.value(), Transaction.class);

        String txId = tx.getTransactionId();
        if (txId != null && auditLog.containsKey(txId)) {
            duplicatesSkipped.incrementAndGet();
            log.debug("Duplicate skipped: txId={}", txId);
            return;
        }

        AuditRecord audit = new AuditRecord();
        audit.setTransactionId(txId);
        audit.setCustomerId(tx.getCustomerId());
        audit.setRawPayload(record.value());
        audit.setPartition(record.partition());
        audit.setOffset(record.offset());
        audit.setAuditedAt(Instant.now());

        if (txId != null) {
            auditLog.put(txId, audit);
        }
        auditRecords.incrementAndGet();

        log.debug("Audit recorded: txId={} partition={} offset={}",
                txId, record.partition(), record.offset());
    }

    private void sendToDlq(ConsumerRecord<String, String> record) {
        try {
            ProducerRecord<String, String> dlqRecord = new ProducerRecord<>(dlqTopic, record.key(), record.value());
            dlqRecord.headers().add(new RecordHeader("dlq-reason", "max-retries-exceeded".getBytes(StandardCharsets.UTF_8)));
            dlqRecord.headers().add(new RecordHeader("original-topic", record.topic().getBytes(StandardCharsets.UTF_8)));
            dlqRecord.headers().add(new RecordHeader("original-partition", String.valueOf(record.partition()).getBytes(StandardCharsets.UTF_8)));
            dlqRecord.headers().add(new RecordHeader("original-offset", String.valueOf(record.offset()).getBytes(StandardCharsets.UTF_8)));

            kafkaTemplate.send(dlqRecord);
            dlqCount.incrementAndGet();

            Map<String, Object> dlqEntry = new LinkedHashMap<>();
            dlqEntry.put("originalPartition", record.partition());
            dlqEntry.put("originalOffset", record.offset());
            dlqEntry.put("reason", "max-retries-exceeded");
            dlqEntry.put("sentAt", Instant.now().toString());
            dlqMessages.add(dlqEntry);

            log.warn("Sent to DLQ: partition={} offset={} topic={}", record.partition(), record.offset(), dlqTopic);
        } catch (Exception ex) {
            log.error("Failed to send to DLQ: partition={} offset={} error={}",
                    record.partition(), record.offset(), ex.getMessage());
        }
    }

    // --- Public accessors for controller ---

    public Collection<AuditRecord> getAuditLog() {
        return Collections.unmodifiableCollection(auditLog.values());
    }

    public List<Map<String, Object>> getDlqMessages() {
        return Collections.unmodifiableList(dlqMessages);
    }

    public Map<String, Object> getMetrics() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("messagesConsumed", messagesConsumed.get());
        m.put("auditRecords", auditRecords.get());
        m.put("duplicatesSkipped", duplicatesSkipped.get());
        m.put("processingErrors", processingErrors.get());
        m.put("dlqCount", dlqCount.get());
        m.put("manualCommits", manualCommits.get());
        m.put("startedAt", startedAt.toString());
        m.put("lastMessageAt", lastMessageAt != null ? lastMessageAt.toString() : null);
        m.put("lastCommitAt", lastCommitAt != null ? lastCommitAt.toString() : null);
        return m;
    }
}
