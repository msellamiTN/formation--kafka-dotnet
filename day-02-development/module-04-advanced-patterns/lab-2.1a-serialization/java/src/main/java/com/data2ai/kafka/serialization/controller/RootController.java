package com.data2ai.kafka.serialization.controller;

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
        response.put("application", "EBanking Serialization API");
        response.put("version", "1.0.0");
        response.put("description", "Avro serialization with Schema Registry integration");
        response.put("endpoints", Map.of(
            "health", "/actuator/health",
            "transactions", "/api/v1/transactions",
            "schema", "/api/v1/schema"
        ));
        response.put("status", "running");
        return response;
    }
}
