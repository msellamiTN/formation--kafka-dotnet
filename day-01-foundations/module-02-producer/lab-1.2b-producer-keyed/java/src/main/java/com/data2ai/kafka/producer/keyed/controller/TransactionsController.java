package com.data2ai.kafka.producer.keyed.controller;

import com.data2ai.kafka.producer.keyed.model.Transaction;
import com.data2ai.kafka.producer.keyed.service.TransactionProducerService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

@RestController
@RequestMapping("/api/v1/transactions")
public class TransactionsController {

    private final TransactionProducerService producerService;

    public TransactionsController(TransactionProducerService producerService) {
        this.producerService = producerService;
    }

    @PostMapping
    public CompletableFuture<ResponseEntity<Map<String, Object>>> create(@Valid @RequestBody Transaction tx) throws Exception {
        return producerService.sendAsync(tx)
                .thenApply(ResponseEntity::ok);
    }

    @PostMapping("/batch")
    public CompletableFuture<ResponseEntity<Map<String, Object>>> batch(@Valid @RequestBody List<Transaction> txs) {
        CompletableFuture<?>[] futures = txs.stream().map(tx -> {
            try {
                return producerService.sendAsync(tx);
            } catch (Exception e) {
                CompletableFuture<Map<String, Object>> failed = new CompletableFuture<>();
                failed.completeExceptionally(e);
                return failed;
            }
        }).toArray(CompletableFuture[]::new);

        return CompletableFuture.allOf(futures)
                .thenApply(_ignored -> ResponseEntity.ok(Map.of(
                        "status", "PRODUCED",
                        "count", txs.size()
                )));
    }
}
