package com.data2ai.kafka.testing.unit;

import com.data2ai.kafka.testing.model.Transaction;
import com.data2ai.kafka.testing.service.TransactionProducerService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.producer.MockProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringSerializer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for TransactionProducerService using MockProducer.
 * No real Kafka broker needed - tests run instantly.
 */
class TransactionProducerTest {

    private static final String TOPIC = "banking.transactions";

    private MockProducer<String, String> mockProducer;
    private TransactionProducerService service;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        mockProducer = new MockProducer<>(true, new StringSerializer(), new StringSerializer());
        objectMapper = new ObjectMapper();
        objectMapper.findAndRegisterModules();
        service = new TransactionProducerService(mockProducer, objectMapper, TOPIC);
    }

    @AfterEach
    void tearDown() {
        service.close();
    }

    @Test
    @DisplayName("Should produce a transaction to the correct topic")
    void shouldProduceToCorrectTopic() throws Exception {
        Transaction tx = new Transaction("FR7630001000111", "FR7630001000222",
                new BigDecimal("150.00"), "TRANSFER", "CUST-001");

        service.send(tx);

        List<ProducerRecord<String, String>> history = mockProducer.history();
        assertEquals(1, history.size());
        assertEquals(TOPIC, history.get(0).topic());
    }

    @Test
    @DisplayName("Should use customerId as message key")
    void shouldUseCustomerIdAsKey() throws Exception {
        Transaction tx = new Transaction("FR7630001000111", "FR7630001000222",
                new BigDecimal("250.00"), "PAYMENT", "CUST-KEY-123");

        service.send(tx);

        ProducerRecord<String, String> record = mockProducer.history().get(0);
        assertEquals("CUST-KEY-123", record.key());
    }

    @Test
    @DisplayName("Should serialize transaction as JSON value")
    void shouldSerializeAsJson() throws Exception {
        Transaction tx = new Transaction("FR7630001000111", "FR7630001000222",
                new BigDecimal("500.00"), "DEPOSIT", "CUST-002");
        tx.setDescription("Unit test transaction");

        service.send(tx);

        String value = mockProducer.history().get(0).value();
        assertNotNull(value);

        Transaction deserialized = objectMapper.readValue(value, Transaction.class);
        assertEquals("CUST-002", deserialized.getCustomerId());
        assertEquals(0, new BigDecimal("500.00").compareTo(deserialized.getAmount()));
        assertEquals("DEPOSIT", deserialized.getType());
        assertEquals("Unit test transaction", deserialized.getDescription());
    }

    @Test
    @DisplayName("Should produce multiple transactions in order")
    void shouldProduceMultipleInOrder() throws Exception {
        for (int i = 1; i <= 5; i++) {
            Transaction tx = new Transaction("FR7630001000111", "FR7630001000222",
                    new BigDecimal(i * 100), "TRANSFER", "CUST-00" + i);
            service.send(tx);
        }

        assertEquals(5, mockProducer.history().size());
        assertEquals("CUST-001", mockProducer.history().get(0).key());
        assertEquals("CUST-005", mockProducer.history().get(4).key());
    }

    @Test
    @DisplayName("Should handle send failure gracefully")
    void shouldHandleSendFailure() {
        MockProducer<String, String> failingProducer = new MockProducer<>(
                false, new StringSerializer(), new StringSerializer());
        TransactionProducerService failingService =
                new TransactionProducerService(failingProducer, objectMapper, TOPIC);

        Transaction tx = new Transaction("FR7630001000111", "FR7630001000222",
                new BigDecimal("100.00"), "TRANSFER", "CUST-FAIL");

        assertDoesNotThrow(() -> failingService.send(tx));

        // Complete with error
        RuntimeException error = new RuntimeException("Broker unavailable");
        failingProducer.errorNext(error);

        assertEquals(1, failingProducer.history().size());
        failingService.close();
    }
}
