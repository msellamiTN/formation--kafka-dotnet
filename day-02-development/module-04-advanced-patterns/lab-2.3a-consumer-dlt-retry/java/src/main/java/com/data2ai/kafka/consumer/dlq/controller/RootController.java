package com.data2ai.kafka.consumer.dlq.controller;

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
        response.put("application", "EBanking Consumer with DLT/Retry");
        response.put("version", "1.0.0");
        response.put("description", "Consumer with Dead Letter Topic and retry mechanisms");
        response.put("endpoints", Map.of(
            "health", "/actuator/health",
            "stats", "/api/v1/stats",
            "dlt", "/api/v1/dlt",
            "retry", "/api/v1/retry"
        ));
        response.put("status", "running");
        return response;
    }
}
