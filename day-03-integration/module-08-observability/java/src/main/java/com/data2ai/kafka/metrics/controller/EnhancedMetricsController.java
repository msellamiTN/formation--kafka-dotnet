package com.data2ai.kafka.metrics.controller;

import com.data2ai.kafka.metrics.service.KafkaMetricsService;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.concurrent.CompletableFuture;

@RestController
@RequestMapping("/api/v2/metrics")
public class EnhancedMetricsController {

    @Autowired
    private KafkaMetricsService kafkaMetricsService;

    @Autowired
    private OpenTelemetry openTelemetry;

    private final Tracer tracer;
    private final Meter meter;

    // Custom metrics
    private final io.opentelemetry.api.metrics.Counter apiRequestCounter;
    private final io.opentelemetry.api.metrics.Histogram apiResponseTime;
    private final io.opentelemetry.api.metrics.Gauge kafkaClusterHealthGauge;

    public EnhancedMetricsController() {
        this.tracer = openTelemetry.getTracer("EnhancedMetricsController", "1.0.0");
        this.meter = openTelemetry.getMeter("EnhancedMetricsController", "1.0.0");
        
        // Initialize custom metrics
        this.apiRequestCounter = meter.counterBuilder("api_requests_total")
                .setDescription("Total number of API requests")
                .setUnit("1")
                .build();
        
        this.apiResponseTime = meter.histogramBuilder("api_response_time_seconds")
                .setDescription("API response time in seconds")
                .setUnit("s")
                .build();
        
        this.kafkaClusterHealthGauge = meter.gaugeBuilder("kafka_cluster_health_status")
                .setDescription("Kafka cluster health status (1=healthy, 0=unhealthy)")
                .setUnit("1")
                .build();
    }

    @GetMapping("/cluster/health")
    public ResponseEntity<?> getClusterHealth() {
        Span span = tracer.spanBuilder("get-cluster-health").startSpan();
        try (Scope scope = span.makeCurrent()) {
            long startTime = System.nanoTime();
            apiRequestCounter.add(1);
            
            try {
                Map<String, Object> health = kafkaMetricsService.getClusterHealth();
                boolean isHealthy = "HEALTHY".equals(health.get("status"));
                
                // Update health gauge
                kafkaClusterHealthGauge.set(isHealthy ? 1 : 0);
                
                // Record response time
                double responseTime = (System.nanoTime() - startTime) / 1_000_000_000.0;
                apiResponseTime.record(responseTime);
                
                span.setAttribute("cluster.healthy", isHealthy);
                span.setAttribute("cluster.broker_count", (Integer) health.get("brokerCount"));
                
                return ResponseEntity.ok(health);
            } catch (Exception e) {
                span.recordException(e);
                kafkaClusterHealthGauge.set(0);
                throw e;
            }
        } finally {
            span.end();
        }
    }

    @GetMapping("/topics")
    public ResponseEntity<?> getTopics() {
        Span span = tracer.spanBuilder("get-topics").startSpan();
        try (Scope scope = span.makeCurrent()) {
            long startTime = System.nanoTime();
            apiRequestCounter.add(1, io.opentelemetry.api.common.Attributes.builder()
                    .put("endpoint", "topics")
                    .build());
            
            try {
                Map<String, Object> topics = kafkaMetricsService.getTopics();
                
                // Record response time
                double responseTime = (System.nanoTime() - startTime) / 1_000_000_000.0;
                apiResponseTime.record(responseTime, io.opentelemetry.api.common.Attributes.builder()
                        .put("endpoint", "topics")
                        .build());
                
                span.setAttribute("topics.count", (Integer) topics.get("count"));
                
                return ResponseEntity.ok(topics);
            } catch (Exception e) {
                span.recordException(e);
                throw e;
            }
        } finally {
            span.end();
        }
    }

    @GetMapping("/consumers")
    public ResponseEntity<?> getConsumerGroups() {
        Span span = tracer.spanBuilder("get-consumer-groups").startSpan();
        try (Scope scope = span.makeCurrent()) {
            long startTime = System.nanoTime();
            apiRequestCounter.add(1, io.opentelemetry.api.common.Attributes.builder()
                    .put("endpoint", "consumers")
                    .build());
            
            try {
                Map<String, Object> consumers = kafkaMetricsService.getConsumerGroups();
                
                // Record response time
                double responseTime = (System.nanoTime() - startTime) / 1_000_000_000.0;
                apiResponseTime.record(responseTime, io.opentelemetry.api.common.Attributes.builder()
                        .put("endpoint", "consumers")
                        .build());
                
                span.setAttribute("consumers.count", (Integer) consumers.get("count"));
                
                return ResponseEntity.ok(consumers);
            } catch (Exception e) {
                span.recordException(e);
                throw e;
            }
        } finally {
            span.end();
        }
    }

    @GetMapping("/performance")
    public ResponseEntity<?> getPerformanceMetrics() {
        Span span = tracer.spanBuilder("get-performance-metrics").startSpan();
        try (Scope scope = span.makeCurrent()) {
            long startTime = System.nanoTime();
            apiRequestCounter.add(1, io.opentelemetry.api.common.Attributes.builder()
                    .put("endpoint", "performance")
                    .build());
            
            try {
                // Simulate performance metrics collection
                Map<String, Object> performance = Map.of(
                    "jvm_memory_used", Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory(),
                    "jvm_memory_max", Runtime.getRuntime().maxMemory(),
                    "active_threads", Thread.activeCount(),
                    "system_load", ManagementFactory.getOperatingSystemMXBean().getSystemLoadAverage()
                );
                
                // Record response time
                double responseTime = (System.nanoTime() - startTime) / 1_000_000_000.0;
                apiResponseTime.record(responseTime, io.opentelemetry.api.common.Attributes.builder()
                        .put("endpoint", "performance")
                        .build());
                
                span.setAttribute("performance.jvm_memory_used", (Long) performance.get("jvm_memory_used"));
                span.setAttribute("performance.active_threads", (Integer) performance.get("active_threads"));
                
                return ResponseEntity.ok(performance);
            } catch (Exception e) {
                span.recordException(e);
                throw e;
            }
        } finally {
            span.end();
        }
    }

    @PostMapping("/trace/test")
    public ResponseEntity<?> testTracing(@RequestBody Map<String, Object> payload) {
        Span span = tracer.spanBuilder("trace-test").startSpan();
        try (Scope scope = span.makeCurrent()) {
            apiRequestCounter.add(1, io.opentelemetry.api.common.Attributes.builder()
                    .put("endpoint", "trace-test")
                    .put("test_type", payload.getOrDefault("type", "default"))
                    .build());
            
            span.setAttribute("test.payload_size", payload.toString().length());
            
            // Simulate some work
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            
            return ResponseEntity.ok(Map.of(
                "status", "success",
                "trace_id", span.getSpanContext().getTraceId(),
                "span_id", span.getSpanContext().getSpanId()
            ));
        } finally {
            span.end();
        }
    }
}
