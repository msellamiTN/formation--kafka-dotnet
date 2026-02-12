package com.data2ai.kafka.consumer.balance.controller;

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
        response.put("application", "EBanking Balance Consumer");
        response.put("version", "1.0.0");
        response.put("description", "Balance tracking consumer with rebalancing support");
        response.put("endpoints", Map.of(
            "health", "/actuator/health",
            "balances", "/api/v1/balances",
            "customer_balance", "/api/v1/balances/{customerId}",
            "rebalancing", "/api/v1/rebalancing",
            "stats", "/api/v1/stats"
        ));
        response.put("status", "running");
        return response;
    }
}
