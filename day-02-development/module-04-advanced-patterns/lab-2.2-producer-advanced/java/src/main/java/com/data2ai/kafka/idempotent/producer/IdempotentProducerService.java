package com.data2ai.kafka.idempotent.producer;

import com.data2ai.kafka.idempotent.model.Transaction;
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
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class IdempotentProducerService {

    private static final Logger log = LoggerFactory.getLogger(IdempotentProducerService.class);

    private final KafkaTemplate<String, Transaction> kafkaTemplate;

    @Value("${app.kafka.topic:banking.transactions}")
    private String topic;

    private final AtomicInteger sentCount = new AtomicInteger(0);
    private final AtomicInteger failedCount = new AtomicInteger(0);
    private final AtomicLong totalLatencyMs = new AtomicLong(0);

    public IdempotentProducerService(KafkaTemplate<String, Transaction> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public Transaction sendIdempotentTransaction(Transaction transaction) {
        long startTime = System.currentTimeMillis();
        try {
            transaction.setTransactionId(UUID.randomUUID().toString());
            transaction.setTimestamp(Instant.now());
            transaction.setStatus(Transaction.TransactionStatus.PENDING);

            String key = transaction.getCustomerId();

            log.info("Sending idempotent transaction: {} | Amount: {} {} | Customer: {}",
                    transaction.getTransactionId(),
                    transaction.getAmount(),
                    transaction.getCurrency(),
                    transaction.getCustomerId());

            CompletableFuture<SendResult<String, Transaction>> future =
                    kafkaTemplate.send(topic, key, transaction);

            SendResult<String, Transaction> result = future.get();

            transaction.setStatus(Transaction.TransactionStatus.COMPLETED);
            if (transaction.getMetadata() == null) {
                transaction.setMetadata(new HashMap<>());
            }
            transaction.getMetadata().put("partition", result.getRecordMetadata().partition());
            transaction.getMetadata().put("offset", result.getRecordMetadata().offset());
            transaction.getMetadata().put("idempotent", true);

            sentCount.incrementAndGet();
            totalLatencyMs.addAndGet(System.currentTimeMillis() - startTime);

            log.info("Idempotent transaction sent: {} | Partition: {} | Offset: {}",
                    transaction.getTransactionId(),
                    result.getRecordMetadata().partition(),
                    result.getRecordMetadata().offset());

            return transaction;

        } catch (Exception e) {
            transaction.setStatus(Transaction.TransactionStatus.FAILED);
            failedCount.incrementAndGet();
            log.error("Failed to send idempotent transaction: {} | Error: {}",
                    transaction.getTransactionId(), e.getMessage());
            throw new RuntimeException("Failed to send idempotent transaction", e);
        }
    }

    public void sendBatch(List<Transaction> transactions) {
        for (Transaction transaction : transactions) {
            sendIdempotentTransaction(transaction);
        }
        log.info("Batch of {} idempotent transactions sent", transactions.size());
    }

    public Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("totalSent", sentCount.get());
        stats.put("totalFailed", failedCount.get());
        int sent = sentCount.get();
        stats.put("averageLatencyMs", sent > 0 ? totalLatencyMs.get() / sent : 0);
        stats.put("idempotenceEnabled", true);
        stats.put("acksConfig", "all");
        return stats;
    }
}
