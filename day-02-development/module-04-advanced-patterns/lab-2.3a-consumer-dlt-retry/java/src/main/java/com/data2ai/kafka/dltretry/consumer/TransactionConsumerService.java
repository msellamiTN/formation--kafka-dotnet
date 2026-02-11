package com.data2ai.kafka.dltretry.consumer;

import com.data2ai.kafka.dltretry.model.DltRecord;
import com.data2ai.kafka.dltretry.model.Transaction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class TransactionConsumerService {

    private static final Logger log = LoggerFactory.getLogger(TransactionConsumerService.class);

    private final KafkaTemplate<String, Object> kafkaTemplate;

    @Value("${app.kafka.dlt-topic:banking.transactions.dlq}")
    private String dltTopic;

    private final AtomicInteger processedCount = new AtomicInteger(0);
    private final AtomicInteger retriedCount = new AtomicInteger(0);
    private final AtomicInteger dltCount = new AtomicInteger(0);
    private final List<Transaction> processedTransactions = Collections.synchronizedList(new ArrayList<>());
    private final List<DltRecord> dltRecords = Collections.synchronizedList(new ArrayList<>());

    public TransactionConsumerService(KafkaTemplate<String, Object> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    @KafkaListener(topics = "${app.kafka.topic:banking.transactions}", groupId = "dlt-retry-consumer-group")
    public void consume(Transaction transaction) {
        log.info("Processing transaction: {} | Amount: {} {}",
                transaction.getTransactionId(),
                transaction.getAmount(),
                transaction.getCurrency());

        try {
            // Simulate processing with potential failures
            processTransaction(transaction);

            transaction.setStatus(Transaction.TransactionStatus.COMPLETED);
            processedTransactions.add(transaction);
            processedCount.incrementAndGet();

            if (processedTransactions.size() > 1000) {
                processedTransactions.subList(0, processedTransactions.size() - 1000).clear();
            }

            log.info("Transaction processed successfully: {}", transaction.getTransactionId());

        } catch (Exception e) {
            log.error("Processing failed for transaction: {} | Error: {} | Sending to DLT",
                    transaction.getTransactionId(), e.getMessage());
            sendToDlt(transaction, e);
            throw e;
        }
    }

    private void processTransaction(Transaction transaction) {
        // Simulate failures for specific scenarios
        if (transaction.getAmount() != null && transaction.getAmount().compareTo(new BigDecimal("99999")) > 0) {
            throw new RuntimeException("Amount exceeds processing limit");
        }
        if ("INVALID".equals(transaction.getCustomerId())) {
            throw new RuntimeException("Invalid customer ID");
        }
    }

    private void sendToDlt(Transaction transaction, Exception error) {
        try {
            DltRecord dltRecord = new DltRecord();
            dltRecord.setOriginalTransactionId(transaction.getTransactionId());
            dltRecord.setErrorMessage(error.getMessage());
            dltRecord.setErrorType(error.getClass().getSimpleName());
            dltRecord.setRetryCount(3);
            dltRecord.setFailedAt(Instant.now());
            dltRecord.setOriginalTransaction(transaction);

            kafkaTemplate.send(dltTopic, transaction.getTransactionId(), dltRecord);
            dltRecords.add(dltRecord);
            dltCount.incrementAndGet();

            if (dltRecords.size() > 500) {
                dltRecords.subList(0, dltRecords.size() - 500).clear();
            }

            log.info("Transaction sent to DLT: {} | Reason: {}",
                    transaction.getTransactionId(), error.getMessage());
        } catch (Exception e) {
            log.error("Failed to send to DLT: {}", e.getMessage());
        }
    }

    public List<Transaction> getProcessedTransactions() {
        return new ArrayList<>(processedTransactions);
    }

    public List<DltRecord> getDltRecords() {
        return new ArrayList<>(dltRecords);
    }

    public Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("processed", processedCount.get());
        stats.put("retried", retriedCount.get());
        stats.put("sentToDlt", dltCount.get());
        return stats;
    }
}
