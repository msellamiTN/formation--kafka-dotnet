package com.data2ai.kafka.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

/**
 * Root controller to provide welcome message and API information.
 */
@RestController
public class RootController {

    @GetMapping("/")
    public Map<String, Object> home() {
        Map<String, Object> response = new HashMap<>();
        response.put("application", "EBanking Kafka Streams - Real-time Processing");
        response.put("version", "1.0.0");
        response.put("description", "Kafka Streams processing for sales aggregation, windowing, and enrichment");
        response.put("endpoints", Map.of(
                "health", "/actuator/health",
                "post_sale", "/api/v1/sales",
                "stats_by_product", "/api/v1/stats/by-product",
                "stats_per_minute", "/api/v1/stats/per-minute",
                "store_all", "/api/v1/stores/{storeName}/all",
                "store_key", "/api/v1/stores/{storeName}/{key}"
        ));
        response.put("status", "running");
        return response;
    }
}
