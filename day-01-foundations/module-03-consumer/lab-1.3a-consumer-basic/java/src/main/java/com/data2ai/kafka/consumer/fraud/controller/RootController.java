package com.data2ai.kafka.consumer.fraud.controller;

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
        response.put("application", "EBanking Fraud Detection Consumer");
        response.put("version", "1.0.0");
        response.put("description", "Fraud detection consumer for banking transactions");
        response.put("endpoints", Map.of(
            "health", "/actuator/health",
            "alerts", "/api/v1/alerts",
            "stats", "/api/v1/stats"
        ));
        response.put("status", "running");
        return response;
    }
}
