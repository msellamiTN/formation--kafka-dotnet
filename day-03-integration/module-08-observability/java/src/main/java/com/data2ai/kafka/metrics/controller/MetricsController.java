package com.data2ai.kafka.metrics.controller;

import com.data2ai.kafka.metrics.service.KafkaMetricsService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * REST controller exposing Kafka cluster health and metrics.
 */
@RestController
@RequestMapping("/api/v1/metrics")
public class MetricsController {

    private final KafkaMetricsService metricsService;

    public MetricsController(KafkaMetricsService metricsService) {
        this.metricsService = metricsService;
    }

    @GetMapping("/cluster")
    public ResponseEntity<Map<String, Object>> clusterHealth() {
        return ResponseEntity.ok(metricsService.getClusterHealth());
    }

    @GetMapping("/consumers")
    public ResponseEntity<Map<String, Object>> consumerGroups() {
        return ResponseEntity.ok(metricsService.getConsumerGroups());
    }

    @GetMapping("/topics")
    public ResponseEntity<Map<String, Object>> topics() {
        return ResponseEntity.ok(metricsService.getTopics());
    }
}
