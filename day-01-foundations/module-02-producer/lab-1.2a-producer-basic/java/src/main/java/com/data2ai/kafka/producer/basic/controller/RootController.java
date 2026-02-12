package com.data2ai.kafka.producer.basic.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.HashMap;
import java.util.Map;

/**
 * Root controller to provide welcome message and API information
 */
@RestController
public class RootController {

    @GetMapping("/")
    public Map<String, Object> home() {
        Map<String, Object> response = new HashMap<>();
        response.put("application", "EBanking Producer API - Basic");
        response.put("version", "1.0.0");
        response.put("description", "Basic Kafka producer for banking transactions");
        response.put("endpoints", Map.of(
            "health", "/actuator/health",
            "transactions", "/api/v1/transactions",
            "transactions_batch", "/api/v1/transactions/batch"
        ));
        response.put("status", "running");
        return response;
    }
}
