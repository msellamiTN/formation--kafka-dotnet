package com.data2ai.kafka.testing.unit;

import com.data2ai.kafka.testing.model.Transaction;
import com.data2ai.kafka.testing.service.TransactionConsumerService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.MockConsumer;
import org.apache.kafka.clients.consumer.OffsetResetStrategy;
import org.apache.kafka.common.TopicPartition;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Duration;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for TransactionConsumerService using MockConsumer.
 * No real Kafka broker needed - tests run instantly.
 */
class TransactionConsumerTest {

    private static final String TOPIC = "banking.transactions";

    private MockConsumer<String, String> mockConsumer;
    private TransactionConsumerService service;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        mockConsumer = new MockConsumer<>(OffsetResetStrategy.EARLIEST);
        objectMapper = new ObjectMapper();
        objectMapper.findAndRegisterModules();
        service = new TransactionConsumerService(mockConsumer, objectMapper, TOPIC);
    }

    @AfterEach
    void tearDown() {
        service.close();
    }

    private void preparePartition() {
        TopicPartition tp = new TopicPartition(TOPIC, 0);
        mockConsumer.rebalance(Collections.singletonList(tp));
        Map<TopicPartition, Long> beginningOffsets = new HashMap<>();
        beginningOffsets.put(tp, 0L);
        mockConsumer.updateBeginningOffsets(beginningOffsets);
    }

    @Test
    @DisplayName("Should consume and deserialize transactions")
    void shouldConsumeTransactions() throws Exception {
        preparePartition();

        Transaction tx = new Transaction("FR7630001000111", "FR7630001000222",
                new BigDecimal("300.00"), "TRANSFER", "CUST-001");
        String json = objectMapper.writeValueAsString(tx);

        mockConsumer.addRecord(new ConsumerRecord<>(TOPIC, 0, 0L, "CUST-001", json));

        List<Transaction> result = service.poll(Duration.ofMillis(100));
        assertEquals(1, result.size());
        assertEquals("CUST-001", result.get(0).getCustomerId());
        assertEquals(0, new BigDecimal("300.00").compareTo(result.get(0).getAmount()));
    }

    @Test
    @DisplayName("Should handle empty poll result")
    void shouldHandleEmptyPoll() {
        preparePartition();

        List<Transaction> result = service.poll(Duration.ofMillis(100));
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("Should consume multiple transactions in batch")
    void shouldConsumeBatch() throws Exception {
        preparePartition();

        for (int i = 0; i < 3; i++) {
            Transaction tx = new Transaction("FR7630001000111", "FR7630001000222",
                    new BigDecimal((i + 1) * 100), "PAYMENT", "CUST-00" + i);
            String json = objectMapper.writeValueAsString(tx);
            mockConsumer.addRecord(new ConsumerRecord<>(TOPIC, 0, i, "CUST-00" + i, json));
        }

        List<Transaction> result = service.poll(Duration.ofMillis(100));
        assertEquals(3, result.size());
    }

    @Test
    @DisplayName("Should skip malformed records without crashing")
    void shouldSkipMalformedRecords() throws Exception {
        preparePartition();

        // Add a malformed record
        mockConsumer.addRecord(new ConsumerRecord<>(TOPIC, 0, 0L, "BAD", "not-valid-json{{{"));

        // Add a valid record after it
        Transaction tx = new Transaction("FR7630001000111", "FR7630001000222",
                new BigDecimal("100.00"), "TRANSFER", "CUST-GOOD");
        String json = objectMapper.writeValueAsString(tx);
        mockConsumer.addRecord(new ConsumerRecord<>(TOPIC, 0, 1L, "CUST-GOOD", json));

        List<Transaction> result = service.poll(Duration.ofMillis(100));
        assertEquals(1, result.size());
        assertEquals("CUST-GOOD", result.get(0).getCustomerId());
    }
}
