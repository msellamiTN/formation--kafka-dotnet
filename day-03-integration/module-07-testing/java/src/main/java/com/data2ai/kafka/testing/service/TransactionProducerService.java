package com.data2ai.kafka.testing.service;

import com.data2ai.kafka.testing.model.Transaction;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;

import java.util.concurrent.Future;

/**
 * Simple transaction producer service.
 * Designed to be testable with MockProducer.
 */
public class TransactionProducerService {

    private final Producer<String, String> producer;
    private final ObjectMapper objectMapper;
    private final String topic;

    public TransactionProducerService(Producer<String, String> producer,
                                       ObjectMapper objectMapper,
                                       String topic) {
        this.producer = producer;
        this.objectMapper = objectMapper;
        this.topic = topic;
    }

    /**
     * Send a transaction to Kafka using customerId as key.
     */
    public Future<RecordMetadata> send(Transaction tx) throws Exception {
        String key = tx.getCustomerId();
        String value = objectMapper.writeValueAsString(tx);
        ProducerRecord<String, String> record = new ProducerRecord<>(topic, key, value);
        return producer.send(record);
    }

    public void close() {
        producer.close();
    }
}
