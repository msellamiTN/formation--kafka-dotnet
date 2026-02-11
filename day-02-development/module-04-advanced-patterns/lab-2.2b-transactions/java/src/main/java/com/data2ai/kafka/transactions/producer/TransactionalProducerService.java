package com.data2ai.kafka.transactions.producer;

import com.data2ai.kafka.transactions.model.Transaction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class TransactionalProducerService {

    private static final Logger log = LoggerFactory.getLogger(TransactionalProducerService.class);

    private final KafkaTemplate<String, Transaction> kafkaTemplate;

    @Value("${app.kafka.topic:banking.transactions}")
    private String topic;

    private final AtomicInteger committedCount = new AtomicInteger(0);
    private final AtomicInteger abortedCount = new AtomicInteger(0);

    public TransactionalProducerService(KafkaTemplate<String, Transaction> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public Transaction sendTransactional(Transaction transaction) {
        transaction.setTransactionId(UUID.randomUUID().toString());
        transaction.setTimestamp(Instant.now());
        transaction.setStatus(Transaction.TransactionStatus.PENDING);

        try {
            SendResult<String, Transaction> result = kafkaTemplate.executeInTransaction(ops -> {
                try {
                    return ops.send(topic, transaction.getCustomerId(), transaction).get();
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            });

            transaction.setStatus(Transaction.TransactionStatus.COMPLETED);
            if (transaction.getMetadata() == null) {
                transaction.setMetadata(new HashMap<>());
            }
            transaction.getMetadata().put("partition", result.getRecordMetadata().partition());
            transaction.getMetadata().put("offset", result.getRecordMetadata().offset());
            transaction.getMetadata().put("transactional", true);

            committedCount.incrementAndGet();
            log.info("Transactional send committed: {} | Partition: {} | Offset: {}",
                    transaction.getTransactionId(),
                    result.getRecordMetadata().partition(),
                    result.getRecordMetadata().offset());

            return transaction;

        } catch (Exception e) {
            transaction.setStatus(Transaction.TransactionStatus.ABORTED);
            abortedCount.incrementAndGet();
            log.error("Transactional send aborted: {} | Error: {}",
                    transaction.getTransactionId(), e.getMessage());
            throw new RuntimeException("Transaction aborted", e);
        }
    }

    public void sendTransactionalBatch(List<Transaction> transactions) {
        try {
            kafkaTemplate.executeInTransaction(ops -> {
                for (Transaction tx : transactions) {
                    tx.setTransactionId(UUID.randomUUID().toString());
                    tx.setTimestamp(Instant.now());
                    tx.setStatus(Transaction.TransactionStatus.PENDING);
                    try {
                        ops.send(topic, tx.getCustomerId(), tx).get();
                        tx.setStatus(Transaction.TransactionStatus.COMPLETED);
                    } catch (Exception e) {
                        throw new RuntimeException("Batch item failed", e);
                    }
                }
                return null;
            });
            committedCount.addAndGet(transactions.size());
            log.info("Transactional batch committed: {} transactions", transactions.size());
        } catch (Exception e) {
            abortedCount.incrementAndGet();
            for (Transaction tx : transactions) {
                tx.setStatus(Transaction.TransactionStatus.ABORTED);
            }
            log.error("Transactional batch aborted: {}", e.getMessage());
            throw new RuntimeException("Transactional batch aborted", e);
        }
    }

    public Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("committed", committedCount.get());
        stats.put("aborted", abortedCount.get());
        stats.put("transactional", true);
        stats.put("isolationLevel", "read_committed");
        return stats;
    }
}
