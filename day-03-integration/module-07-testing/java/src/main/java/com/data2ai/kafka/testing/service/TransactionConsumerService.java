package com.data2ai.kafka.testing.service;

import com.data2ai.kafka.testing.model.Transaction;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.Consumer;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Simple transaction consumer service.
 * Designed to be testable with MockConsumer.
 */
public class TransactionConsumerService {

    private final Consumer<String, String> consumer;
    private final ObjectMapper objectMapper;
    private final String topic;

    public TransactionConsumerService(Consumer<String, String> consumer,
                                       ObjectMapper objectMapper,
                                       String topic) {
        this.consumer = consumer;
        this.objectMapper = objectMapper;
        this.topic = topic;
    }

    /**
     * Subscribe and poll for transactions.
     */
    public List<Transaction> poll(Duration timeout) {
        consumer.subscribe(Collections.singletonList(topic));
        ConsumerRecords<String, String> records = consumer.poll(timeout);

        List<Transaction> transactions = new ArrayList<>();
        for (ConsumerRecord<String, String> record : records) {
            try {
                Transaction tx = objectMapper.readValue(record.value(), Transaction.class);
                transactions.add(tx);
            } catch (Exception e) {
                // Skip malformed records
            }
        }
        return transactions;
    }

    public void close() {
        consumer.close();
    }
}
