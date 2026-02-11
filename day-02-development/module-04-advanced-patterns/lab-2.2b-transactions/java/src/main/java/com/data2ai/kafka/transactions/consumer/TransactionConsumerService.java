package com.data2ai.kafka.transactions.consumer;

import com.data2ai.kafka.transactions.model.Transaction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class TransactionConsumerService {

    private static final Logger log = LoggerFactory.getLogger(TransactionConsumerService.class);

    private final List<Transaction> consumedTransactions = Collections.synchronizedList(new ArrayList<>());
    private final AtomicInteger consumedCount = new AtomicInteger(0);

    @KafkaListener(topics = "${app.kafka.topic:banking.transactions}", groupId = "transaction-consumer-group")
    public void consume(Transaction transaction) {
        log.info("Consumed transaction: {} | Status: {} | Amount: {} {}",
                transaction.getTransactionId(),
                transaction.getStatus(),
                transaction.getAmount(),
                transaction.getCurrency());

        consumedTransactions.add(transaction);
        consumedCount.incrementAndGet();

        if (consumedTransactions.size() > 1000) {
            consumedTransactions.subList(0, consumedTransactions.size() - 1000).clear();
        }
    }

    public List<Transaction> getConsumedTransactions() {
        return new ArrayList<>(consumedTransactions);
    }

    public int getConsumedCount() {
        return consumedCount.get();
    }
}
