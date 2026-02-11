package com.data2ai.kafka.transactions.controller;

import com.data2ai.kafka.transactions.dto.CreateTransactionRequest;
import com.data2ai.kafka.transactions.model.Transaction;
import com.data2ai.kafka.transactions.consumer.TransactionConsumerService;
import com.data2ai.kafka.transactions.producer.TransactionalProducerService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class TransactionController {

    private final TransactionalProducerService producerService;
    private final TransactionConsumerService consumerService;

    public TransactionController(TransactionalProducerService producerService,
                                  TransactionConsumerService consumerService) {
        this.producerService = producerService;
        this.consumerService = consumerService;
    }

    @PostMapping("/transactions/transactional")
    public ResponseEntity<Map<String, Object>> sendTransactional(
            @RequestBody CreateTransactionRequest request) {
        Transaction transaction = mapRequest(request);
        Transaction result = producerService.sendTransactional(transaction);

        Map<String, Object> response = new HashMap<>();
        response.put("message", "Transactional send committed");
        response.put("transactionId", result.getTransactionId());
        response.put("status", result.getStatus());
        response.put("metadata", result.getMetadata());
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PostMapping("/transactions/batch")
    public ResponseEntity<Map<String, Object>> sendBatch(
            @RequestBody List<CreateTransactionRequest> requests) {
        List<Transaction> transactions = new ArrayList<>();
        for (CreateTransactionRequest req : requests) {
            transactions.add(mapRequest(req));
        }
        producerService.sendTransactionalBatch(transactions);

        Map<String, Object> response = new HashMap<>();
        response.put("message", "Transactional batch committed");
        response.put("count", transactions.size());
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/consumed")
    public ResponseEntity<Map<String, Object>> getConsumed() {
        Map<String, Object> response = new HashMap<>();
        response.put("count", consumerService.getConsumedCount());
        response.put("transactions", consumerService.getConsumedTransactions());
        return ResponseEntity.ok(response);
    }

    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStats() {
        return ResponseEntity.ok(producerService.getStats());
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("service", "EBanking Transactional Producer API");
        health.put("status", "UP");
        health.put("timestamp", Instant.now());
        return ResponseEntity.ok(health);
    }

    private Transaction mapRequest(CreateTransactionRequest req) {
        Transaction t = new Transaction();
        t.setFromAccount(req.getFromAccount());
        t.setToAccount(req.getToAccount());
        t.setAmount(req.getAmount());
        t.setCurrency(req.getCurrency());
        t.setType(req.getType());
        t.setDescription(req.getDescription());
        t.setCustomerId(req.getCustomerId());
        return t;
    }
}
