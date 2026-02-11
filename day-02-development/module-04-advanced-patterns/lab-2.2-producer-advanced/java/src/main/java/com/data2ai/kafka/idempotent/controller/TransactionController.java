package com.data2ai.kafka.idempotent.controller;

import com.data2ai.kafka.idempotent.dto.CreateTransactionRequest;
import com.data2ai.kafka.idempotent.model.Transaction;
import com.data2ai.kafka.idempotent.producer.IdempotentProducerService;
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

    private final IdempotentProducerService producerService;

    public TransactionController(IdempotentProducerService producerService) {
        this.producerService = producerService;
    }

    @PostMapping("/transactions/idempotent")
    public ResponseEntity<Map<String, Object>> sendIdempotentTransaction(
            @RequestBody CreateTransactionRequest request) {
        Transaction transaction = new Transaction();
        transaction.setFromAccount(request.getFromAccount());
        transaction.setToAccount(request.getToAccount());
        transaction.setAmount(request.getAmount());
        transaction.setCurrency(request.getCurrency());
        transaction.setType(request.getType());
        transaction.setDescription(request.getDescription());
        transaction.setCustomerId(request.getCustomerId());

        Transaction result = producerService.sendIdempotentTransaction(transaction);

        Map<String, Object> response = new HashMap<>();
        response.put("message", "Idempotent transaction submitted");
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
            Transaction t = new Transaction();
            t.setFromAccount(req.getFromAccount());
            t.setToAccount(req.getToAccount());
            t.setAmount(req.getAmount());
            t.setCurrency(req.getCurrency());
            t.setType(req.getType());
            t.setDescription(req.getDescription());
            t.setCustomerId(req.getCustomerId());
            transactions.add(t);
        }

        producerService.sendBatch(transactions);

        Map<String, Object> response = new HashMap<>();
        response.put("message", "Batch submitted with idempotent guarantee");
        response.put("count", transactions.size());

        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStats() {
        return ResponseEntity.ok(producerService.getStats());
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("service", "EBanking Idempotent Producer API");
        health.put("status", "UP");
        health.put("timestamp", Instant.now());
        return ResponseEntity.ok(health);
    }
}
