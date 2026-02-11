package com.data2ai.kafka.dltretry.controller;

import com.data2ai.kafka.dltretry.consumer.TransactionConsumerService;
import com.data2ai.kafka.dltretry.model.DltRecord;
import com.data2ai.kafka.dltretry.model.Transaction;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class DltRetryController {

    private final TransactionConsumerService consumerService;

    public DltRetryController(TransactionConsumerService consumerService) {
        this.consumerService = consumerService;
    }

    @GetMapping("/processed")
    public ResponseEntity<Map<String, Object>> getProcessed() {
        List<Transaction> transactions = consumerService.getProcessedTransactions();
        Map<String, Object> response = new HashMap<>();
        response.put("count", transactions.size());
        response.put("transactions", transactions);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/dlq")
    public ResponseEntity<Map<String, Object>> getDlq() {
        List<DltRecord> records = consumerService.getDltRecords();
        Map<String, Object> response = new HashMap<>();
        response.put("count", records.size());
        response.put("records", records);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStats() {
        return ResponseEntity.ok(consumerService.getStats());
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("service", "EBanking DLT Retry Consumer API");
        health.put("status", "UP");
        health.put("timestamp", Instant.now());
        return ResponseEntity.ok(health);
    }
}
