package com.data2ai.kafka.metrics.controller;

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
        response.put("application", "EBanking Kafka Metrics Dashboard");
        response.put("version", "1.0.0");
        response.put("description", "Kafka cluster health monitoring, consumer lag tracking, and Prometheus metrics");
        response.put("endpoints", Map.of(
                "health", "/actuator/health",
                "prometheus", "/actuator/prometheus",
                "cluster_health", "/api/v1/metrics/cluster",
                "consumer_groups", "/api/v1/metrics/consumers",
                "topics", "/api/v1/metrics/topics"
        ));
        response.put("status", "running");
        return response;
    }
}
