package com.data2ai.kafka.serialization.controller;

import com.data2ai.kafka.serialization.dto.CreateTransactionRequest;
import com.data2ai.kafka.serialization.model.Transaction;
import com.data2ai.kafka.serialization.model.TransactionV2;
import com.data2ai.kafka.serialization.producer.SerializationProducerService;
import com.data2ai.kafka.serialization.consumer.SerializationConsumerService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.ArrayList;

@RestController
@RequestMapping("/api/v1")
public class TransactionController {
    
    private final SerializationProducerService producerService;
    private final SerializationConsumerService consumerService;
    
    public TransactionController(SerializationProducerService producerService,
                               SerializationConsumerService consumerService) {
        this.producerService = producerService;
        this.consumerService = consumerService;
    }
    
    @PostMapping("/transactions")
    public ResponseEntity<Map<String, String>> createTransaction(@RequestBody CreateTransactionRequest request) {
        Transaction transaction = new Transaction();
        transaction.setFromAccount(request.getFromAccount());
        transaction.setToAccount(request.getToAccount());
        transaction.setAmount(request.getAmount());
        transaction.setCurrency(request.getCurrency());
        transaction.setType(request.getType());
        transaction.setDescription(request.getDescription());
        transaction.setCustomerId(request.getCustomerId());
        transaction.setCategory(request.getCategory());
        
        try {
            producerService.sendTransaction(transaction);
            return ResponseEntity.ok(Map.of(
                "message", "Transaction submitted for processing",
                "status", "PENDING",
                "transactionId", transaction.getTransactionId()
            ));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to submit transaction"));
        }
    }
    
    @PostMapping("/transactions/v2")
    public ResponseEntity<Map<String, String>> createTransactionV2(@RequestBody TransactionV2 transactionV2) {
        try {
            producerService.sendTransactionWithSchemaV2(transactionV2);
            return ResponseEntity.ok(Map.of(
                "message", "V2 Transaction submitted for processing",
                "status", "PENDING",
                "transactionId", transactionV2.getTransactionId()
            ));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to submit V2 transaction"));
        }
    }
    
    @PostMapping("/transactions/batch")
    public ResponseEntity<Map<String, Object>> createTransactionsBatch(@RequestBody List<CreateTransactionRequest> requests) {
        List<Transaction> transactions = new ArrayList<>();
        
        for (CreateTransactionRequest request : requests) {
            Transaction transaction = new Transaction();
            transaction.setFromAccount(request.getFromAccount());
            transaction.setToAccount(request.getToAccount());
            transaction.setAmount(request.getAmount());
            transaction.setCurrency(request.getCurrency());
            transaction.setType(request.getType());
            transaction.setDescription(request.getDescription());
            transaction.setCustomerId(request.getCustomerId());
            transaction.setCategory(request.getCategory());
            transactions.add(transaction);
        }
        
        try {
            producerService.sendTransactionBatch(transactions);
            return ResponseEntity.ok(Map.of(
                "total", requests.size(),
                "message", "Batch processing completed"
            ));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to submit batch transactions"));
        }
    }
    
    @GetMapping("/transactions/statistics")
    public ResponseEntity<Map<String, Object>> getStatistics() {
        return ResponseEntity.ok(consumerService.getStatistics());
    }
    
    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of(
            "status", "UP",
            "service", "EBanking Serialization API",
            "timestamp", Instant.now().toString()
        ));
    }
}
