package com.data2ai.kafka.consumer.fraud.controller;

import com.data2ai.kafka.consumer.fraud.model.FraudAlert;
import com.data2ai.kafka.consumer.fraud.service.FraudDetectionService;
import com.data2ai.kafka.consumer.fraud.service.FraudMetrics;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1")
public class FraudController {

    private final FraudDetectionService fraudService;

    public FraudController(FraudDetectionService fraudService) {
        this.fraudService = fraudService;
    }

    @GetMapping("/alerts")
    public ResponseEntity<List<FraudAlert>> alerts() {
        return ResponseEntity.ok(fraudService.getAlerts());
    }

    @GetMapping("/stats")
    public ResponseEntity<FraudMetrics> stats() {
        return ResponseEntity.ok(fraudService.getMetrics());
    }
}
