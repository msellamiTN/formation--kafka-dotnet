package com.data2ai.kafka.consumer.audit.controller;

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
        response.put("application", "EBanking Audit Consumer");
        response.put("version", "1.0.0");
        response.put("description", "Audit consumer with manual commit and DLQ support");
        response.put("endpoints", Map.of(
            "health", "/actuator/health",
            "audit", "/api/v1/audit",
            "dlq", "/api/v1/dlq",
            "stats", "/api/v1/stats"
        ));
        response.put("status", "running");
        return response;
    }
}
