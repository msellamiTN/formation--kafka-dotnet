package com.data2ai.kafka.consumer.audit.controller;

import com.data2ai.kafka.consumer.audit.model.AuditRecord;
import com.data2ai.kafka.consumer.audit.service.AuditService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Collection;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class AuditController {

    private final AuditService auditService;

    public AuditController(AuditService auditService) {
        this.auditService = auditService;
    }

    @GetMapping("/audit")
    public ResponseEntity<Collection<AuditRecord>> auditLog() {
        return ResponseEntity.ok(auditService.getAuditLog());
    }

    @GetMapping("/dlq")
    public ResponseEntity<List<Map<String, Object>>> dlqMessages() {
        return ResponseEntity.ok(auditService.getDlqMessages());
    }

    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> stats() {
        return ResponseEntity.ok(auditService.getMetrics());
    }
}
